use adora_node_api::{AdoraNode, Event, arrow};
use eyre::{ContextCompat, bail};

fn main() -> eyre::Result<()> {
    let (_node, mut events) = AdoraNode::init_from_env()?;
    let mut received_count: i64 = 0;

    while let Some(event) = events.recv() {
        match event {
            Event::Input { id, data, .. } if id.as_str() == "values" => {
                // Python sends pa.array([i * 10], type=pa.int64()) so we receive a single i64
                let values: &[i64] = data
                    .as_any()
                    .downcast_ref::<arrow::array::Int64Array>()
                    .context("expected Int64Array from Python sender")?
                    .values();
                if values.len() != 1 {
                    bail!("expected 1 element from Python, got {}", values.len());
                }
                let expected = received_count * 10;
                if values[0] != expected {
                    bail!("value mismatch: expected {expected}, got {}", values[0]);
                }
                println!("rust-receiver: validated value {}", values[0]);
                received_count += 1;
            }
            Event::Stop(_) => {
                println!("rust-receiver: stopping after {received_count} messages");
                break;
            }
            _ => {}
        }
    }

    if received_count < 5 {
        bail!(
            "rust-receiver got only {received_count} messages from Python sender (expected >= 5)"
        );
    }
    println!("rust-receiver: SUCCESS - validated {received_count} messages");
    Ok(())
}
