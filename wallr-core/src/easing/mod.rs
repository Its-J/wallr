//! Easing curves used by animation packages and validation tooling.

use crate::animation::Easing;

/// Evaluate an easing curve at `t` in the inclusive range `0..=1`.
pub fn sample(curve: &Easing, t: f32) -> f32 {
    let t = t.clamp(0.0, 1.0);
    match curve {
        Easing::Linear => t,
        // Cubic ease-in: accelerates smoothly from rest.
        Easing::EaseIn => t * t * t,
        // Cubic ease-out: decelerates with natural momentum into rest.
        Easing::EaseOut => 1.0 - (1.0 - t).powi(3),
        // Quintic ease-in-out (smoothstep5): C2-continuous at endpoints,
        // eliminating mechanical velocity jumps.
        Easing::EaseInOut => quintic_ease_in_out(t),
        // Emphatic: restrained back-out overshoot curve for purposeful, sharp reveals.
        Easing::Emphatic => back_out(t, 1.20158),
        // Critically-damped spring settling: zero vibration, tactile physical weight.
        Easing::Spring => spring(t, 1.0, 200.0, 28.0),
    }
}

/// Quintic ease-in-out: 6t^5 - 15t^4 + 10t^3.
/// Velocity and acceleration are zero at both endpoints.
fn quintic_ease_in_out(t: f32) -> f32 {
    t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
}

/// Back-out curve: starts at 0, subtle overshoot at mid-to-late phase, settles cleanly at 1.
fn back_out(t: f32, c: f32) -> f32 {
    let c3 = c + 1.0;
    let u = t - 1.0;
    1.0 + c3 * u * u * u + c * u * u
}

/// Evaluate a cubic Bézier timing curve using Newton iteration and bisection.
pub fn cubic_bezier(t: f32, x1: f32, y1: f32, x2: f32, y2: f32) -> f32 {
    let t = t.clamp(0.0, 1.0);
    let mut u = t;
    for _ in 0..12 {
        let x = bezier(u, x1, x2) - t;
        let dx = 3.0 * (1.0 - u).powi(2) * x1
            + 6.0 * (1.0 - u) * u * (x2 - x1)
            + 3.0 * u.powi(2) * (1.0 - x2);
        if dx.abs() < 1e-6 {
            break;
        }
        u = (u - x / dx).clamp(0.0, 1.0);
    }
    bezier(u, y1, y2)
}

fn bezier(t: f32, p1: f32, p2: f32) -> f32 {
    3.0 * (1.0 - t).powi(2) * t * p1 + 3.0 * (1.0 - t) * t.powi(2) * p2 + t.powi(3)
}

/// Evaluate a damped spring. Parameters are mass, stiffness, and damping.
pub fn spring(t: f32, mass: f32, stiffness: f32, damping: f32) -> f32 {
    let omega = (stiffness / mass.max(0.001)).sqrt();
    let zeta = damping / (2.0 * (stiffness * mass).sqrt().max(0.001));
    let e = (-zeta * omega * t * 6.0).exp();
    if zeta < 1.0 {
        let wd = omega * (1.0 - zeta * zeta).sqrt();
        1.0 - e * ((wd * t * 6.0).cos() + zeta * omega / wd * (wd * t * 6.0).sin())
    } else {
        1.0 - e * (1.0 + omega * t * 6.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn curves_start_and_end_at_expected_points() {
        for curve in [
            Easing::Linear,
            Easing::EaseIn,
            Easing::EaseOut,
            Easing::EaseInOut,
            Easing::Emphatic,
            Easing::Spring,
        ] {
            assert!((sample(&curve, 0.0)).abs() < 0.01);
            assert!((sample(&curve, 1.0) - 1.0).abs() < 0.01);
        }
    }

    #[test]
    fn quintic_is_monotone() {
        let mut prev = 0.0f32;
        for i in 0..=100 {
            let t = i as f32 / 100.0;
            let v = quintic_ease_in_out(t);
            assert!(v >= prev - 1e-6, "quintic should be monotonic");
            prev = v;
        }
    }
}
