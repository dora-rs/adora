use std::collections::BTreeMap;

pub(crate) struct TopicSubscriber {
    outputs_by_daemon: BTreeMap<
        dora_message::common::DaemonId,
        Vec<(dora_message::id::NodeId, dora_message::id::DataId)>,
    >,
    sender: Option<tokio::sync::mpsc::Sender<Vec<u8>>>,
}

impl TopicSubscriber {
    pub(crate) fn new(
        outputs_by_daemon: BTreeMap<
            dora_message::common::DaemonId,
            Vec<(dora_message::id::NodeId, dora_message::id::DataId)>,
        >,
        sender: tokio::sync::mpsc::Sender<Vec<u8>>,
    ) -> Self {
        Self {
            outputs_by_daemon,
            sender: Some(sender),
        }
    }

    pub(crate) fn outputs_by_daemon(
        &self,
    ) -> &BTreeMap<
        dora_message::common::DaemonId,
        Vec<(dora_message::id::NodeId, dora_message::id::DataId)>,
    > {
        &self.outputs_by_daemon
    }

    pub(crate) async fn send_frame(&mut self, payload: Vec<u8>) -> eyre::Result<()> {
        let sender = self
            .sender
            .as_ref()
            .ok_or_else(|| eyre::eyre!("subscriber is closed"))?;
        sender
            .send(payload)
            .await
            .map_err(|_| eyre::eyre!("WS topic subscriber channel closed"))?;
        Ok(())
    }

    pub(crate) fn is_closed(&self) -> bool {
        match &self.sender {
            None => true,
            Some(sender) => sender.is_closed(),
        }
    }

    pub(crate) fn close(&mut self) {
        self.sender = None;
    }
}
