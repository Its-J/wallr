//! # wallr-core
//!
//! Core library for Wallr — a native, GPU-accelerated Wayland wallpaper engine.

// `wgpu-core`'s internal types (`Hub`/`Registry`/…) are deep enough to trip
// rustc's `recursion_depth_exceeding_limit` future-compat lint whenever a
// closure captures renderer state (e.g. `Arc<Mutex<RenderState>>` in
// `spawn_blocking`). That depth comes from wgpu, not from our code, and the
// types were accepted under the old limit — so allow the lint here until a
// wgpu upgrade shallows those internals. See rust-lang/rust#159228.
#![allow(recursion_depth_exceeding_limit)]

pub mod animated;
pub mod animation;
pub mod cache;
pub mod cli;
pub mod config;
pub mod custom_effects;
pub mod daemon;
pub mod easing;
pub mod ipc;
pub mod packages;
pub mod preview;
pub mod renderer;
pub mod shader;
pub mod theme;
pub mod video;
pub mod wallpaper;
