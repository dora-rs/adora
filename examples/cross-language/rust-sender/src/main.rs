use adora_node_api::{AdoraNode, Event, IntoArrow, adora_core::config::DataId};
use eyre::Context;

fn main() -> eyre::Result<()> {
    let (mut node, mut events) = AdoraNode::init_from_env()?;
    let output = DataId::from("values".to_owned());

    // Send 10 messages with known values: [0, 10, 20, ..., 90]
    for i in 0..10 {
        let event = match events.recv() {
            Some(e) => e,
            None => break,
        };
        match event {
            Event::Input { id, metadata, .. } if id.as_str() == "tick" => {
                let value: i64 = i * 10;
                node.send_output(output.clone(), metadata.parameters, value.into_arrow())
                    .context("failed to send output")?;
                println!("rust-sender: sent {value}");
            }
            Event::Stop(_) => break,
            _ => {}
        }
    }
    Ok(())
}
