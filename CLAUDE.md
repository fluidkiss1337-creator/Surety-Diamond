# CLAUDE.md — Handoff Guide for Surety-Diamond

This file provides complete context for any AI assistant or developer working in this repository. It is the authoritative source for project conventions, architecture decisions, and current state.

---

## Project Identity

**Surety-Diamond** is a modular, upgradeable smart contract system implementing **EIP-2535 Diamond Standard** for on-chain financial compliance. It targets enterprise supply chain finance (SCF) platforms operating across multiple jurisdictions with high-volume payment flows.

**Owner:** Fluid Kiss Consultations — fluidkiss1337@gmail.com
**License:** MIT
**Solidity:** ^0.8.24 | **Toolchain:** Foundry | **CI:** GitHub Actions

---

## Repository Layout

```
Surety-Diamond/
├── fluid-compliance/                    # Main Solidity project (Foundry workspace)
│   ├── src/
│   │   ├── diamond/
│   │   │   ├── SuretyDiamond.sol        # EIP-2535 proxy (75 LOC) — fallback router + 48h timelock
│   │   │   └── DiamondInit.sol          # One-shot atomic initialization (52 LOC)
│   │   ├── facets/                      # 13 facet contracts (~2,639 LOC total)
│   │   ├── interfaces/                  # 14 interfaces (I*.sol) — events, errors, function sigs
│   │   └── libraries/
│   │       ├── LibAppStorage.sol        # Central shared storage struct (581 LOC, 12 domain sections)
│   │       ├── LibDiamond.sol           # EIP-2535 routing table + ownership (275 LOC)
│   │       └── LibRoles.sol             # RBAC with 15 role constants (139 LOC)
│   ├── test/
│   │   ├── helpers/DiamondTestHelper.sol # Shared test base — deploys full diamond (390 LOC)
│   │   ├── *.t.sol                      # 14 unit test files
│   │   └── fuzz/                        # 2 fuzz test files
│   ├── script/Deploy.s.sol              # Production deployment (13 facets, 102 selectors)
│   ├── foundry.toml                     # Compiler config (0.8.24, optimizer 200 runs, via_ir)
│   ├── remappings.txt                   # forge-std only
│   ├── .solhint.json                    # Solhint linting rules
│   └── README.md                        # Technical reference and API docs (16 KB)
├── .github/workflows/ci.yml            # CI: forge build + test + solhint lint
├── compliance-facets-specification.md   # Full feature specification (52 KB, 1604 lines)
├── AUDIT-REPORT.md                      # Architecture audit report (April 2026)
├── README.md                            # Project overview (stakeholder-facing)
├── LICENSE                              # MIT
└── CLAUDE.md                            # This file
```

---

## Architecture

### How the Diamond Works

All logic lives in **facets** — independent contracts whose functions are `delegatecall`ed through a single `SuretyDiamond` proxy. Storage is shared via `LibAppStorage` using a deterministic storage slot.

```
User / Protocol
      │
      ▼
SuretyDiamond (proxy)
      │  msg.sig → routing table lookup
      │  delegatecall to facet
      ▼
[ KYCFacet | AMLFacet | SanctionsFacet | InvoiceRegistryFacet | ... ]
      │
      ▼  (all share)
LibAppStorage  →  keccak256("surety.compliance.diamond.storage")
LibDiamond     →  keccak256("diamond.standard.diamond.storage")
```

### Critical Invariants

1. **Never add instance variables to facets.** All state goes through `LibAppStorage.appStorage()`.
2. **Never bypass role checks.** Every state-changing function must use `LibRoles.checkRole()` via a modifier.
3. **Every state-changing function must emit an event.** Events must have indexed fields for the primary entity and a timestamp.
4. **Never use string revert messages.** Use custom errors only (gas efficiency, enforced by solhint).
5. **Post-initialization upgrades require the 48-hour timelock.** Direct `diamondCut()` is blocked once `timelockDuration != 0`.
6. **Append-only for audit data.** Audit entries, upgrade history, and security incidents are immutable arrays.

### Storage Slots

| Slot | Contents |
|------|----------|
| `keccak256("surety.compliance.diamond.storage")` | `AppStorage` — all application state (KYC, AML, sanctions, invoices, etc.) |
| `keccak256("diamond.standard.diamond.storage")` | `DiamondStorage` — EIP-2535 routing table, facet registry, ERC-165 |

These are separate. No collision risk.

---

## Facets (13 total, 102 selectors)

| Facet | Selectors | Role Gate | Domain |
|-------|-----------|-----------|--------|
| `DiamondCutFacet` | 3 | Owner | Timelocked facet upgrades (schedule/execute) |
| `DiamondLoupeFacet` | 5 | None (view) | EIP-2535 introspection, ERC-165 |
| `KYCFacet` | 7 | KYC_VERIFIER | FATF KYC lifecycle, Merkle document proofs, PEP detection |
| `AMLFacet` | 6 | AML_ANALYST | Risk scoring (0–1000), SAR filing, transaction monitoring |
| `SanctionsFacet` | 9 | SANCTIONS_MANAGER | OFAC/UN/EU/UK Merkle-proof screening (5 list types) |
| `InvoiceRegistryFacet` | 9 | FACTOR/SELLER | Invoice registration, double-factoring prevention, factoring agreements |
| `FATCACRSFacet` | 8 | TAX_OFFICER/COMPLIANCE_OFFICER | Tax classification, withholding calculation, reporting obligations |
| `JurisdictionFacet` | 9 | COMPLIANCE_OFFICER | Multi-jurisdiction config, cross-border assessment, blocked pairs |
| `AuditFacet` | 9 | AUDITOR | Hash-chained immutable audit trail with typed events |
| `EmergencyFacet` | 4 | EMERGENCY_ADMIN/PAUSER | System pause/unpause, emergency withdrawal (reentrancy-guarded) |
| `OracleFacet` | 8 | ORACLE | ECDSA-verified data feeds, nonce replay prevention |
| `UpgradeManagerFacet` | 11 | UPGRADE_MANAGER | Storage layout validation, multi-sig proposals, rollback snapshots |
| `SecurityGuardFacet` | 14 | SECURITY_ADMIN | Per-selector rate limiting, circuit breaker, threat registry, address blocking |

---

## Roles (15)

Defined in `LibRoles.sol`. All are `bytes32` constants with `_ROLE` suffix.

| Category | Roles |
|----------|-------|
| Admin | `DEFAULT_ADMIN_ROLE` (0x00), `COMPLIANCE_OFFICER_ROLE`, `EMERGENCY_ADMIN_ROLE` |
| Compliance | `KYC_VERIFIER_ROLE`, `AML_ANALYST_ROLE`, `SANCTIONS_MANAGER_ROLE`, `TAX_OFFICER_ROLE`, `AUDITOR_ROLE` |
| Operations | `ORACLE_ROLE`, `FACTOR_ROLE`, `SELLER_ROLE`, `BUYER_ROLE` |
| Infrastructure | `PAUSER_ROLE`, `UPGRADE_MANAGER_ROLE`, `SECURITY_ADMIN_ROLE` |

**Bootstrap:** During `DiamondInit`, `timelockDuration == 0` allows role grants without admin checks. Once init completes, all role management requires holding the appropriate admin role.

---

## Development

### Prerequisites

- **Foundry** (latest) — `forge`, `cast`, `anvil`
- **Node.js** >= 18 (for solhint)
- **Solidity** ^0.8.24

### Commands (run from `fluid-compliance/`)

```bash
forge build              # compile all contracts
forge build --sizes      # compile with contract size report
forge test               # run all 176 tests
forge test -vvv          # verbose (shows traces on failure)
forge test --match-test "test_markAsReported"  # run specific test
forge coverage           # code coverage report
forge fmt                # format Solidity files
npx solhint 'src/**/*.sol'  # lint (matches CI)
```

### Config Files

| File | Purpose |
|------|---------|
| `foundry.toml` | Compiler (0.8.24), optimizer (200 runs, via_ir), CI fuzz/invariant profiles |
| `remappings.txt` | `forge-std/=lib/forge-std/src/` (only external dependency) |
| `.solhint.json` | Linting rules: custom errors enforced, NatSpec required, assembly allowed |
| `.env.example` | Deployment variables (PRIVATE_KEY, OWNER_ADDRESS, RPC_URL, ETHERSCAN_API_KEY) |

### CI Pipeline (`.github/workflows/ci.yml`)

Two parallel jobs on push to `main` and all PRs:
1. **Forge tests** — `forge build --sizes` + `forge test -vvv`
2. **Solhint** — `solhint 'src/**/*.sol'`

---

## Coding Conventions

### Style Rules

- **SPDX:** `// SPDX-License-Identifier: MIT`
- **Pragma:** `pragma solidity ^0.8.24;`
- **Errors:** Custom errors only — never `require()` with strings
- **NatSpec:** `@notice`, `@param`, `@return` on all `public`/`external` functions. Use `@inheritdoc` when implementing interface functions.
- **Section dividers:** `// ============================================================`
- **Line length:** 120 characters max

### Naming

| Item | Convention | Example |
|------|-----------|---------|
| Facets | `PascalCaseFacet` | `SecurityGuardFacet` |
| Interfaces | `IPascalCase` | `ISecurityGuardFacet` |
| Libraries | `LibPascalCase` | `LibAppStorage` |
| Constants | `SCREAMING_SNAKE_CASE` | `MAX_RISK_SCORE` |
| Roles | `keccak256("NAME_ROLE")` | `COMPLIANCE_OFFICER_ROLE` |
| Events | Past tense / completed action | `KYCApproved`, `SARFiled`, `InvoiceRegistered` |
| Custom errors | Descriptive noun/adjective | `InvalidAdvanceRate`, `EntitySanctioned` |

### Patterns Every Facet Must Follow

```solidity
// 1. Storage access — always via library helper, never direct state vars
LibAppStorage.AppStorage storage s = LibAppStorage.appStorage();

// 2. Role check — via modifier calling LibRoles
modifier onlyComplianceOfficer() {
    LibRoles.checkRole(LibRoles.COMPLIANCE_OFFICER_ROLE);
    _;
}

// 3. Pause check — on all non-emergency state changes
modifier whenNotPaused() {
    if (LibAppStorage.isPaused()) revert SystemPaused();
    _;
}

// 4. Event emission — every state change, with indexed primary entity + timestamp
emit ReportingObligationFulfilled(obligationId, msg.sender, block.timestamp);
```

### System Constants

| Constant | Value | Location |
|----------|-------|----------|
| `MAX_RISK_SCORE` | 1000 | AMLFacet |
| `HIGH_RISK_THRESHOLD` | 750 | AMLFacet |
| `MEDIUM_RISK_THRESHOLD` | 400 | AMLFacet |
| `SAR_FILING_THRESHOLD` | 10,000 * 1e18 | AMLFacet |
| `MIN_TIMELOCK` | 48 hours | DiamondCutFacet |
| `KYC_VALIDITY_PERIOD` | 365 days | KYCFacet |
| `MAX_INVOICE_AMOUNT` | 1e9 * 1e18 | InvoiceRegistryFacet |
| `MIN_ADVANCE_RATE` | 100 bps (1%) | InvoiceRegistryFacet |
| `MAX_ADVANCE_RATE` | 9500 bps (95%) | InvoiceRegistryFacet |
| `FATCA_THRESHOLD` | 50,000 * 1e18 | FATCACRSFacet |
| `CRS_THRESHOLD` | 10,000 * 1e18 | FATCACRSFacet |
| `WITHHOLDING_RATE_US` | 3000 bps (30%) | FATCACRSFacet |
| `ORACLE_DATA_EXPIRY` | 24 hours | OracleFacet |
| `MAX_ORACLES_PER_TYPE` | 5 | OracleFacet |

---

## Test Suite

**176 tests** across 16 test contracts + 1 shared helper.

| Category | Count | Purpose |
|----------|-------|---------|
| Unit tests | 164 | Per-facet coverage (every facet has a dedicated test file) |
| Fuzz tests | 6 | AML risk score bounds, invoice amount/rate bounds |
| Integration tests | 3 | Full compliance flow, emergency pause, sanctions enforcement |
| Selector validation | 2 | All 102 selectors verified against Deploy.s.sol |
| Shared helper | 1 file | `DiamondTestHelper.sol` (390 LOC) — deploys full diamond, pre-configures roles |

### Test Accounts (from DiamondTestHelper)

| Account | Roles Granted |
|---------|--------------|
| `owner` | DEFAULT_ADMIN, COMPLIANCE_OFFICER, EMERGENCY_ADMIN |
| `verifier` | KYC_VERIFIER |
| `analyst` | AML_ANALYST |
| `officer` | COMPLIANCE_OFFICER, TAX_OFFICER |
| `sanctionsMgr` | SANCTIONS_MANAGER |
| `seller` | SELLER |
| `buyer` | BUYER |
| `factor` | FACTOR |
| `auditor` | AUDITOR |
| `oracle` | ORACLE |
| `pauser` | PAUSER |
| `upgradeMgr` | UPGRADE_MANAGER |
| `securityAdmin` | SECURITY_ADMIN |

### Adding Tests

1. Create `test/NewFacet.t.sol` inheriting `DiamondTestHelper`
2. Use typed interface accessors: `kyc()`, `aml()`, `sanctions()`, `invoice()`, `fatca()`, `jurisdiction()`, `audit()`, `loupe()`, `upgradeManager()`, `securityGuard()`
3. Use `vm.prank(roleHolder)` for role-gated calls
4. Use `vm.expectRevert()` for error cases
5. Use `vm.expectEmit(true, true, false, true)` + `emit Interface.Event(...)` for event verification

---

## Deployment

### Script: `script/Deploy.s.sol`

Single atomic deployment:
1. Deploys all 13 facet contracts
2. Deploys `DiamondInit` initializer
3. Constructs `SuretyDiamond` with all 102 selector cuts + init calldata

### Environment

```bash
cp .env.example .env
# Fill: PRIVATE_KEY, OWNER_ADDRESS, RPC_URL, ETHERSCAN_API_KEY (optional), TREASURY_ADDRESS (optional)
forge script script/Deploy.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
```

### Post-Deployment Bootstrap

After deployment, the owner must grant operational roles externally (no admin facet exists — `LibRoles.grantRole` is internal). This requires a dedicated role-management facet or direct storage writes via a bootstrap script.

---

## Security Features

| Feature | Mechanism | Location |
|---------|-----------|----------|
| 48-hour upgrade timelock | Schedule/execute pattern | DiamondCutFacet |
| Reentrancy guard | Status flag (1=NOT_ENTERED, 2=ENTERED) | LibAppStorage + EmergencyFacet |
| System pause | `whenNotPaused` modifier on all facets | EmergencyFacet |
| Per-selector rate limiting | Sliding window per address per function | SecurityGuardFacet |
| Circuit breaker | Auto-pause on configurable incident threshold | SecurityGuardFacet |
| Auto-block on CRITICAL | Address blocked on CRITICAL security incident | SecurityGuardFacet |
| Multi-sig upgrades | Configurable approval count before execution | UpgradeManagerFacet |
| Pre-upgrade snapshots | Facet state captured for rollback reference | UpgradeManagerFacet |
| Hash-chained audit trail | Each entry hashes the previous (tamper detection) | AuditFacet |
| Merkle proof verification | Sanctions screening + KYC document verification | SanctionsFacet, KYCFacet |
| ECDSA signature verification | Oracle data feed validation with nonce replay prevention | OracleFacet |

### Security Audit History

14 findings resolved (2 CRITICAL, 4 HIGH, 3 MEDIUM, 4 LOW) via `security/remediation-v1` branch. See `AUDIT-REPORT.md` for the full architecture audit.

---

## Regulatory Context

| Region | Frameworks | Implementing Facets |
|--------|-----------|---------------------|
| USA | BSA, PATRIOT Act §312/§319, OFAC, FATCA | KYC, AML, Sanctions, FATCA/CRS |
| EU | MiCA, 6AMLD, GDPR | Jurisdiction, Audit |
| Global | FATF Recommendations, UN sanctions, Basel III/IV | AML, Sanctions |
| UK | HMT Financial Sanctions | Sanctions |

**KYC Levels:** NONE → BASIC → STANDARD → ENHANCED → INSTITUTIONAL

**Sanctions Lists:** OFAC_SDN, OFAC_CONS, UN_SC, EU_CONS, UK_HMT

**Risk Scale:** 0–1000 (LOW < 400 < MEDIUM < 750 < HIGH)

---

## Current State (as of 2026-04-02)

### Complete

- All 13 facets implemented and wired (102 selectors)
- All 3 libraries: LibAppStorage (581 LOC), LibDiamond (275 LOC), LibRoles (139 LOC)
- All 14 interfaces with full NatSpec, events, and custom errors
- Test suite: 176 tests (164 unit + 6 fuzz + 3 integration + 2 selector validation + 1 helper)
- Deploy.s.sol: production deployment script
- CI: GitHub Actions (forge build + test + solhint lint)
- Solhint linting config
- Security remediations: all 14 findings resolved
- Documentation: 4 documents (85+ KB total)
- Architecture audit report (AUDIT-REPORT.md)

### Open Items (from audit)

| # | Item | Priority |
|---|------|----------|
| 1 | No `forge coverage` baseline documented | Medium |
| 2 | No formal invariant tests (`invariant_*` functions) | Medium |
| 3 | SecurityGuardFacet incident queries iterate linearly (needs pagination) | Low |
| 4 | No multi-chain deployment config | Low |
| 5 | Reverted RoleManagerFacet commit in history (branch cleanup) | Low |
| 6 | Storage packing optimization (`systemPaused` + `treasuryAddress` slot sharing) | Low |

---

## Git Workflow

- **Main branch:** `main`
- **Remote:** `fluidkiss1337-creator/Surety-Diamond`
- **Commit style:** Conventional commits — `feat:`, `fix:`, `docs:`, `test:`, `refactor:`
- **Rule:** One logical change per commit
- **Never commit:** Private keys, `.env` files, build artifacts

---

## Documentation Map

| Document | Size | Purpose |
|----------|------|---------|
| `README.md` | 6 KB | Stakeholder overview, architecture diagram, regulatory coverage |
| `fluid-compliance/README.md` | 16 KB | Developer reference: API, roles, deployment, upgrade procedures, security |
| `compliance-facets-specification.md` | 52 KB | Full business/technical specification (1,604 lines) |
| `AUDIT-REPORT.md` | 17 KB | Architecture audit with findings, metrics, and portfolio assessment |
| `CLAUDE.md` | This file | AI/developer handoff guide |

---

## How to Add a New Facet

1. **Interface:** Create `src/interfaces/INewFacet.sol` with events, errors, and function signatures. Full NatSpec required.
2. **Implementation:** Create `src/facets/NewFacet.sol` implementing the interface. Use `LibAppStorage.appStorage()` for state. Add role modifier and `whenNotPaused`. Emit events on all state changes.
3. **Storage:** Add any new fields to the **end** of `AppStorage` struct in `LibAppStorage.sol` (append-only — never reorder existing fields).
4. **Deploy script:** Add facet deployment + selector array to `Deploy.s.sol`. Update the cuts array size.
5. **Test:** Create `test/NewFacet.t.sol` inheriting `DiamondTestHelper`. Add interface accessor to helper if needed.
6. **Selector test:** Update `test/DeploySelectors.t.sol` to verify new selectors.
7. **Documentation:** Update this file's facet table, README badges (test count, facet count, selector count), and `fluid-compliance/README.md`.

---

## Contact

For custom EIP-2535 Diamond contract work (consultation, architecture, creation, testing, implementation): **fluidkiss1337@gmail.com**
