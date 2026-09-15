use serde::{Deserialize, Serialize};
use std::path::Path;
use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};

/// Maximum IPC request size. Prevents unbounded allocations from malformed
/// or malicious clients. 64 KiB is far above any legitimate command
/// (a path + effect params is typically < 2 KiB).
pub const MAX_IPC_BYTES: usize = 64 * 1024;
/// Maximum wallpaper path length accepted over IPC.
pub const MAX_IPC_PATH_LEN: usize = 8192;
/// Maximum monitor name length accepted over IPC.
pub const MAX_MONITOR_LEN: usize = 256;
/// Maximum transition duration accepted over IPC (60s).
pub const MAX_DURATION_MS: u32 = 60_000;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "command", rename_all = "snake_case")]
pub enum IpcCommand {
    Pause {
        #[serde(default)]
        monitor: Option<String>,
    },
    Resume {
        #[serde(default)]
        monitor: Option<String>,
    },
    Reload,
    Seek {
        timestamp_ms: u64,
        #[serde(default)]
        monitor: Option<String>,
    },
    Preview {
        path: String,
        effect: Option<crate::animation::Effect>,
        duration_ms: Option<u32>,
        #[serde(default)]
        no_theme: bool,
        #[serde(default)]
        theme_override: Option<crate::config::ThemeProvider>,
        #[serde(default)]
        monitor: Option<String>,
        #[serde(default)]
        scaling_mode: Option<crate::config::ScalingMode>,
    },
    Stop,
    Status,
    Info {
        #[serde(default)]
        monitor: Option<String>,
    },
    MonitorList,
    MonitorCurrent,
    Blank {
        #[serde(default)]
        monitor: Option<String>,
        #[serde(default)]
        effect: Option<crate::animation::Effect>,
        #[serde(default)]
        duration_ms: Option<u32>,
    },
    Restore {
        #[serde(default)]
        monitor: Option<String>,
        #[serde(default)]
        effect: Option<crate::animation::Effect>,
        #[serde(default)]
        duration_ms: Option<u32>,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IpcResponse {
    pub success: bool,
    pub message: Option<String>,
}

impl IpcResponse {
    pub fn ok() -> Self {
        Self {
            success: true,
            message: None,
        }
    }

    pub fn err(message: impl Into<String>) -> Self {
        Self {
            success: false,
            message: Some(message.into()),
        }
    }
}

/// Validates an IPC command before the daemon acts on it. Returns `Ok(())`
/// when the command is well-formed, or a human-readable reason when it must
/// be rejected. This runs before any filesystem, GPU, or theme work.
pub fn validate_command(cmd: &IpcCommand) -> Result<(), String> {
    fn check_monitor(monitor: &Option<String>) -> Result<(), String> {
        if let Some(name) = monitor {
            if name.is_empty() {
                return Err("monitor name cannot be empty".to_string());
            }
            if name.len() > MAX_MONITOR_LEN {
                return Err(format!("monitor name exceeds {MAX_MONITOR_LEN} bytes"));
            }
            if name.bytes().any(|b| b < 0x20 || b == 0x7f) {
                return Err("monitor name contains control characters".to_string());
            }
            if name.contains('\n') || name.contains('\0') {
                return Err("monitor name contains invalid characters".to_string());
            }
        }
        Ok(())
    }

    fn check_duration(duration_ms: &Option<u32>) -> Result<(), String> {
        if let Some(ms) = duration_ms
            && *ms > MAX_DURATION_MS
        {
            return Err(format!(
                "duration {ms}ms exceeds maximum {MAX_DURATION_MS}ms"
            ));
        }
        Ok(())
    }

    fn check_effect(effect: &Option<crate::animation::Effect>) -> Result<(), String> {
        if let Some(effect) = effect {
            for value in effect_param_values(effect) {
                if !value.is_finite() {
                    return Err("effect parameter must be finite".to_string());
                }
                if value.abs() > 1_000_000.0 {
                    return Err("effect parameter out of range".to_string());
                }
            }
        }
        Ok(())
    }

    fn check_path(path: &str) -> Result<(), String> {
        if path.is_empty() {
            return Err("wallpaper path cannot be empty".to_string());
        }
        if path.len() > MAX_IPC_PATH_LEN {
            return Err(format!("wallpaper path exceeds {MAX_IPC_PATH_LEN} bytes"));
        }
        if path.bytes().any(|b| b == 0) {
            return Err("wallpaper path contains NUL".to_string());
        }
        Ok(())
    }

    match cmd {
        IpcCommand::Pause { monitor } | IpcCommand::Resume { monitor } => check_monitor(monitor),
        IpcCommand::Reload
        | IpcCommand::Stop
        | IpcCommand::Status
        | IpcCommand::MonitorList
        | IpcCommand::MonitorCurrent => Ok(()),
        IpcCommand::Seek {
            timestamp_ms,
            monitor,
        } => {
            check_monitor(monitor)?;
            if *timestamp_ms > 24 * 3600 * 1000 {
                return Err("seek timestamp exceeds 24h".to_string());
            }
            Ok(())
        }
        IpcCommand::Preview {
            path,
            effect,
            duration_ms,
            monitor,
            ..
        } => {
            check_path(path)?;
            check_monitor(monitor)?;
            check_duration(duration_ms)?;
            check_effect(effect)?;
            Ok(())
        }
        IpcCommand::Info { monitor } => check_monitor(monitor),
        IpcCommand::Blank {
            monitor,
            effect,
            duration_ms,
        }
        | IpcCommand::Restore {
            monitor,
            effect,
            duration_ms,
        } => {
            check_monitor(monitor)?;
            check_duration(duration_ms)?;
            check_effect(effect)?;
            Ok(())
        }
    }
}

fn effect_param_values(effect: &crate::animation::Effect) -> Vec<f32> {
    use crate::animation::Effect;
    match effect {
        Effect::Fade(p) => vec![p.from, p.to],
        Effect::Blur(p) => vec![p.from, p.to],
        Effect::Wipe(p) => vec![p.softness, p.angle.unwrap_or(0.0)],
        Effect::Slide(_) => vec![],
        Effect::Zoom(p) => vec![p.from, p.to],
        Effect::Pixelate(p) => vec![p.from, p.to],
        Effect::Ripple(p) => vec![p.frequency, p.amplitude, p.speed],
        Effect::Dissolve(p) => vec![p.scale, p.softness],
        Effect::Wave(p) => vec![p.frequency, p.amplitude, p.angle.unwrap_or(0.0)],
        Effect::Grow(_) | Effect::Outer(_) => vec![],
        Effect::Shader(p) => p.uniforms.values().map(|v| *v as f32).collect(),
    }
}

#[derive(Debug, thiserror::Error)]
pub enum IpcError {
    #[error("daemon not running: {0}")]
    DaemonNotRunning(String),
    #[error("IPC I/O error: {0}")]
    Io(#[from] std::io::Error),
    #[error("protocol serialization/deserialization error: {0}")]
    Protocol(#[from] serde_json::Error),
}

pub async fn send_ipc_command<P: AsRef<Path>>(
    socket_path: P,
    command: IpcCommand,
) -> Result<IpcResponse, IpcError> {
    let mut stream = UnixStream::connect(socket_path)
        .await
        .map_err(|e| IpcError::DaemonNotRunning(e.to_string()))?;

    let req_data = serde_json::to_vec(&command)?;
    stream.write_all(&req_data).await?;
    stream.write_all(b"\n").await?;
    stream.flush().await?;

    let mut reader = BufReader::new(stream);
    let mut response_line = String::new();
    reader.read_line(&mut response_line).await?;

    let response: IpcResponse = serde_json::from_str(&response_line)?;
    Ok(response)
}

async fn write_response(writer: &mut tokio::io::WriteHalf<UnixStream>, response: &IpcResponse) {
    if let Ok(res_data) = serde_json::to_vec(response) {
        let _ = writer.write_all(&res_data).await;
        let _ = writer.write_all(b"\n").await;
        let _ = writer.flush().await;
    }
}

pub async fn start_ipc_server<P, F, Fut>(socket_path: P, handler: F) -> Result<(), IpcError>
where
    P: AsRef<Path>,
    F: Fn(IpcCommand) -> Fut + Send + Sync + 'static,
    Fut: std::future::Future<Output = IpcResponse> + Send + 'static,
{
    let path = socket_path.as_ref();
    if path.exists() {
        let _ = std::fs::remove_file(path);
    }

    let listener = UnixListener::bind(path)?;
    let handler = std::sync::Arc::new(handler);

    tokio::spawn(async move {
        loop {
            match listener.accept().await {
                Ok((stream, _)) => {
                    let handler_clone = handler.clone();
                    tokio::spawn(async move {
                        let (reader, mut writer) = tokio::io::split(stream);
                        let reader = BufReader::new(reader);
                        // Bound the request: `take` caps memory even when a
                        // client never sends a newline.
                        let mut limited = reader.take((MAX_IPC_BYTES + 1) as u64);
                        let mut buf = Vec::with_capacity(1024);
                        let response = match limited.read_until(b'\n', &mut buf).await {
                            Ok(0) => return,
                            Ok(_) if buf.len() > MAX_IPC_BYTES => {
                                IpcResponse::err(format!("request exceeds {MAX_IPC_BYTES} bytes"))
                            }
                            Ok(_) => match serde_json::from_slice::<IpcCommand>(&buf) {
                                Ok(cmd) => match validate_command(&cmd) {
                                    Ok(()) => handler_clone(cmd).await,
                                    Err(reason) => IpcResponse::err(reason),
                                },
                                Err(e) => IpcResponse::err(format!("invalid IPC command: {e}")),
                            },
                            Err(e) => IpcResponse::err(format!("IPC read error: {e}")),
                        };
                        write_response(&mut writer, &response).await;
                    });
                }
                Err(e) => {
                    tracing::error!("IPC accept error: {:?}", e);
                }
            }
        }
    });

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn preview(path: &str) -> IpcCommand {
        IpcCommand::Preview {
            path: path.to_string(),
            effect: None,
            duration_ms: None,
            no_theme: true,
            theme_override: None,
            monitor: None,
            scaling_mode: None,
        }
    }

    #[test]
    fn accepts_well_formed_commands() {
        assert!(validate_command(&preview("/tmp/wall.jpg")).is_ok());
        assert!(validate_command(&IpcCommand::Status).is_ok());
        assert!(
            validate_command(&IpcCommand::Seek {
                timestamp_ms: 1000,
                monitor: Some("DP-1".to_string()),
            })
            .is_ok()
        );
    }

    #[test]
    fn rejects_empty_path_and_oversized_requests() {
        assert!(validate_command(&preview("")).is_err());
        assert!(validate_command(&preview(&"a".repeat(MAX_IPC_PATH_LEN + 1))).is_err());
        assert!(
            validate_command(&IpcCommand::Preview {
                path: "/tmp/w.jpg".to_string(),
                effect: None,
                duration_ms: Some(MAX_DURATION_MS + 1),
                no_theme: true,
                theme_override: None,
                monitor: None,
                scaling_mode: None,
            })
            .is_err()
        );
    }

    #[test]
    fn rejects_bad_monitor_names() {
        assert!(
            validate_command(&IpcCommand::Pause {
                monitor: Some("".to_string())
            })
            .is_err()
        );
        assert!(
            validate_command(&IpcCommand::Pause {
                monitor: Some("a".repeat(MAX_MONITOR_LEN + 1))
            })
            .is_err()
        );
        assert!(
            validate_command(&IpcCommand::Pause {
                monitor: Some("DP-1\n".to_string())
            })
            .is_err()
        );
        // Normal output names are accepted.
        for name in ["DP-1", "HDMI-A-1", "eDP-1", "output-42"] {
            assert!(
                validate_command(&IpcCommand::Pause {
                    monitor: Some(name.to_string())
                })
                .is_ok(),
                "should accept {name}"
            );
        }
    }

    #[test]
    fn rejects_non_finite_effect_params() {
        let effect = crate::animation::Effect::Fade(crate::animation::FadeParams {
            from: f32::NAN,
            to: 1.0,
            easing: crate::animation::Easing::Linear,
        });
        assert!(
            validate_command(&IpcCommand::Preview {
                path: "/tmp/w.jpg".to_string(),
                effect: Some(effect),
                duration_ms: None,
                no_theme: true,
                theme_override: None,
                monitor: None,
                scaling_mode: None,
            })
            .is_err()
        );
    }

    #[test]
    fn rejects_excessive_seek() {
        assert!(
            validate_command(&IpcCommand::Seek {
                timestamp_ms: 25 * 3600 * 1000,
                monitor: None,
            })
            .is_err()
        );
    }
}
