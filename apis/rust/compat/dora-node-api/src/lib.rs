//! Backward-compatible shim crate that re-exports [`adora_node_api`] under the
//! `dora-node-api` name so that existing dora-hub nodes compile without changes.
//!
//! Usage in dora-hub nodes:
//! ```rust,ignore
//! use dora_node_api::{DoraNode, Event};
//! ```

pub use adora_node_api::*;

// Re-export the crate itself so `dora_node_api::dora_core` works.
pub use adora_node_api::adora_core as dora_core;
