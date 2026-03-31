//! Backward-compatible shim crate that re-exports [`adora_operator_api`] under
//! the `dora-operator-api` name so that existing dora-hub operators compile
//! without changes.
//!
//! Usage in dora-hub operators:
//! ```rust,ignore
//! use dora_operator_api::{DoraOperator, DoraOutputSender, DoraStatus, Event, register_operator};
//! ```

pub use adora_operator_api::*;

// Trait alias: dora-hub operators `impl DoraOperator for T`.
pub use adora_operator_api::AdoraOperator as DoraOperator;
