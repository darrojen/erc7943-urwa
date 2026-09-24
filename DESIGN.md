# ERC-7943 Universal RWA Token — Design Note

## 1. Overview

This project implements a scoped-down version of **ERC-7943: Universal RWA (uRWA) Token**.

ERC-7943 provides a standard interface for fungible tokens representing real-world assets that may require compliance controls. The standard provides mechanisms for checking whether transfers are allowed, freezing tokens, and performing forced transfers when necessary.

For this implementation, I built the token on top of a simple ERC-20 implementation and implemented the ERC-7943 fungible interface.

The implementation deliberately excludes identity/KYC integrations, multi-jurisdiction compliance logic, and upgradeability, as required by the assignment scope.

The main compliance mechanism used in this project is a simple on-chain allowlist. Both the sender and receiver of a normal transfer must be allowlisted.

---

## 2. Implemented Scope

The contract implements the following functionality:

* Basic ERC-20 functionality:

  * `totalSupply`
  * `balanceOf`
  * `transfer`
  * `transferFrom`
  * `approve`
  * `allowance`

* ERC-7943 functionality:

  * `canSend`
  * `canReceive`
  * `canTransfer`
  * `getFrozenTokens`
  * `setFrozenTokens`
  * `forcedTransfer`

* ERC-165 interface detection through `supportsInterface`.

* Administrative allowlist management.

* Amount-based token freezing.

* Forced transfers to an approved recovery address.

* Standard ERC-20 and ERC-7943 events.

The ERC-7943 fungible interface is exposed through ERC-165 using interface ID `0x3edbb4c4`.

---

## 3. Mapping the Implementation to ERC-7943

### `canSend(address account)`

This function provides the account-level check for whether an account is permitted to send tokens.

In this implementation, it returns whether the account is present on the on-chain allowlist.

The allowlist itself is an implementation choice for this assignment. ERC-7943 does not require a specific KYC or compliance provider.

### `canReceive(address account)`

This performs the corresponding account-level receiving check.

An account must be allowlisted to receive tokens through normal transfers.

### `canTransfer(address from, address to, uint256 amount)`

This is the transfer-specific compliance check.

It combines the sender and receiver checks with the frozen-token restriction.

For example, if Alice owns 10,000 tokens and 4,000 are frozen, only 6,000 tokens are considered transferable.

`canTransfer` is a view function and does not modify state.

The actual ERC-20 balance check remains in the transfer execution path. This separates compliance validation from the base token's balance accounting.

### `getFrozenTokens(address account)`

Returns the amount of tokens currently marked as frozen for an account.

The frozen amount is tracked separately from the account's ERC-20 balance.

### `setFrozenTokens(address account, uint256 amount)`

This is the administrative freezing mechanism.

The administrator can set the frozen amount for an account. Setting the amount to zero effectively unfreezes the tokens.

The implementation follows the amount-based freezing model rather than using only a boolean frozen/unfrozen state.

### `forcedTransfer(address from, address to, uint256 amount)`

This provides the administrative forced-transfer mechanism.

Unlike a normal transfer, the operation can move tokens even when those tokens are frozen.

The implementation requires the destination to be an allowlisted receiving address and adjusts the frozen amount when frozen tokens are moved.

Both the ERC-20 `Transfer` event and ERC-7943 `ForcedTransfer` event are emitted.

---

## 4. Hard Design Decisions

### Decision 1 — Using an allowlist as the compliance mechanism

ERC-7943 defines compliance hooks but does not prescribe a particular identity or KYC system.

For this assignment, I used a simple mapping:

`mapping(address => bool) allowlisted`

This makes the compliance rule deterministic and completely on-chain while keeping the implementation within the assignment's scope.

A normal transfer requires both:

* `canSend(from) == true`
* `canReceive(to) == true`

This provides a simple demonstration of how an issuer could connect ERC-7943's validation interface to a compliance system.

### Decision 2 — Representing freezing as an amount

Instead of storing only a boolean frozen state, the implementation stores:

`mapping(address => uint256) _frozenTokens`

This allows part of an account's balance to remain transferable while another part is frozen.

For example:

* Balance = 10,000
* Frozen = 4,000
* Transferable = 6,000

The implementation also allows the frozen amount to exceed the current balance. This follows the amount-based model and means that newly acquired tokens can remain restricted until the frozen amount is reduced.

### Decision 3 — Separating normal and forced transfers

Normal transfers go through the compliance and frozen-token checks.

Forced transfers are a separate administrative operation because their purpose is to allow an issuer or authorized administrator to recover or move assets even when normal transfers are blocked.

When a forced transfer moves frozen tokens, the frozen amount is reduced accordingly.

This preserves the relationship between the account's balance and the amount that remains frozen.

---

## 5. Events

The implementation emits the standard ERC-20 events:

* `Transfer`
* `Approval`

It also implements the relevant ERC-7943 events:

* `ForcedTransfer`
* `Frozen`

The assignment additionally requested a rejected-transfer event, so the implementation contains a custom `TransferRejected` event.

A limitation is that a Solidity event emitted immediately before a transaction reverts will not remain in the final transaction receipt because the entire transaction state, including logs, is reverted.

Therefore, the reliable way to observe a rejected transfer in this implementation is through the revert/error itself. The custom event exists to satisfy the assignment requirement, but it should not be treated as a persistent audit log for reverted transactions.

---

## 6. Testing

The project includes a Foundry test suite covering both successful and unsuccessful operations.

The tests cover:

* Initial token supply and administrator configuration.
* Successful allowlisted transfers.
* ERC-20 approvals and `transferFrom`.
* Frozen-token restrictions.
* Unfreezing.
* Forced transfers.
* Adjustment of frozen amounts after forced transfers.
* Sender allowlist restrictions.
* Receiver allowlist restrictions.
* Non-admin attempts to freeze.
* Non-admin attempts to force-transfer.
* Non-admin attempts to modify the allowlist.
* Forced transfers to non-allowlisted recipients.
* Transfers exceeding an account's balance.
* ERC-165 and ERC-7943 interface detection.
* Frozen amounts exceeding the current balance.

The failure tests demonstrate that the compliance restrictions are enforced rather than merely exposed as view functions.

---

## 7. AI Usage

I used AI assistance primarily during development of the test suite.

AI was used to help generate, organize, and refine Foundry tests covering the required happy paths and failure cases.

I did not treat the generated output as automatically correct. I reviewed the tests against the contract behavior and the ERC-7943 requirements, identified incorrect assumptions, and corrected the test logic where necessary.

For example, an initial freeze test incorrectly calculated Alice's transferable balance after freezing tokens. The test was corrected after checking the actual setup: Alice receives 10,000 tokens, so freezing 4,000 leaves 6,000 transferable tokens.

I also verified the resulting behavior by running the Foundry test suite.

The final contract behavior and design decisions were reviewed by me so that I can explain the implementation during the live defense.

---

## 8. Limitations

This is intentionally a scoped implementation rather than a production-ready RWA token.

It does not implement:

* Real KYC or identity verification.
* Jurisdiction-specific compliance.
* Upgradeability.
* External compliance providers.
* Privacy-preserving compliance.
* Production-grade access-control systems.

The allowlist is only a simplified demonstration of how the ERC-7943 compliance hooks can be connected to a compliance rule.

---

## 9. Conclusion

This implementation demonstrates the main ERC-7943 fungible-token compliance mechanisms within the scope of the assignment.

The contract combines a basic ERC-20 token with transfer validation, account allowlisting, amount-based freezing, administrative forced transfers, standardized events, and ERC-165 interface detection.

The most important design principle is keeping the base token accounting separate from the compliance layer: ERC-20 handles balances and transfers, while ERC-7943 provides the mechanisms needed to determine whether a transfer is permitted and to perform controlled administrative actions when normal transfers are not appropriate.
