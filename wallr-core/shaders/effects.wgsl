struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@group(0) @binding(0) var t_diffuse1: texture_2d<f32>;
@group(0) @binding(1) var s_diffuse1: sampler;
@group(1) @binding(0) var t_diffuse2: texture_2d<f32>;
@group(1) @binding(1) var s_diffuse2: sampler;

struct Uniforms {
    time: f32,
    progress: f32, // 0.0 to 1.0
    effect_type: u32,
    padding: u32,
    resolution: vec2<f32>,
    image_resolution: vec2<f32>,
    old_image_resolution: vec2<f32>,
    param_a: f32,
    param_b: f32,
    param_c: f32,
    param_d: f32,
    origin: vec2<f32>,
    direction: vec2<f32>,
    easing: u32,
    scaling_mode: u32, // 0=Fill, 1=Fit, 2=Stretch, 3=Center, 4=Tile
};

@group(2) @binding(0) var<uniform> uniforms: Uniforms;

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VertexOutput {
    var out: VertexOutput;
    let u = f32((vertex_index << 1u) & 2u);
    let v = f32(vertex_index & 2u);
    out.uv = vec2<f32>(u, 1.0 - v);
    out.clip_position = vec4<f32>(u * 2.0 - 1.0, v * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

// ---------------------------------------------------------------------------
// Easing functions (mirrors wallr-core/src/easing/mod.rs)
// 0 = Linear, 1 = EaseIn, 2 = EaseOut, 3 = EaseInOut, 4 = Emphatic, 5 = Spring
// ---------------------------------------------------------------------------

// Quintic smootherstep (C2 continuous): zero velocity and acceleration at ends
fn ease_in_out(t: f32) -> f32 {
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

fn ease_in(t: f32) -> f32 {
    return t * t * t;
}

fn ease_out(t: f32) -> f32 {
    let u = 1.0 - t;
    return 1.0 - u * u * u;
}

fn emphatic(t: f32) -> f32 {
    let c = 1.20158;
    let c3 = c + 1.0;
    let u = t - 1.0;
    return 1.0 + c3 * u * u * u + c * u * u;
}

fn spring_ease(t: f32) -> f32 {
    let omega = 14.1421356; // sqrt(200.0)
    let zeta = 0.9899495;  // 28.0 / (2 * sqrt(200.0))
    let e = exp(-zeta * omega * t * 6.0);
    let wd = omega * sqrt(max(1.0 - zeta * zeta, 0.0001));
    return 1.0 - e * (cos(wd * t * 6.0) + (zeta * omega / wd) * sin(wd * t * 6.0));
}

fn apply_easing(t: f32, mode: u32) -> f32 {
    if (mode == 0u) {
        return t;
    }
    if (mode == 1u) {
        return ease_in(t);
    }
    if (mode == 2u) {
        return ease_out(t);
    }
    if (mode == 4u) {
        return emphatic(t);
    }
    if (mode == 5u) {
        return spring_ease(t);
    }
    return ease_in_out(t);
}

// ---------------------------------------------------------------------------
// Wallpaper UV scaling
// ---------------------------------------------------------------------------

fn cover_uv(uv: vec2<f32>, image_resolution: vec2<f32>, screen_resolution: vec2<f32>) -> vec2<f32> {
    let screen_ratio = screen_resolution.x / max(screen_resolution.y, 1.0);
    let image_ratio = image_resolution.x / max(image_resolution.y, 1.0);
    var result = uv;
    if (screen_ratio > image_ratio) {
        result.y = (uv.y - 0.5) * (image_ratio / screen_ratio) + 0.5;
    } else {
        result.x = (uv.x - 0.5) * (screen_ratio / image_ratio) + 0.5;
    }
    return result;
}

fn fit_uv(uv: vec2<f32>, image_resolution: vec2<f32>, screen_resolution: vec2<f32>) -> vec2<f32> {
    let screen_ratio = screen_resolution.x / max(screen_resolution.y, 1.0);
    let image_ratio = image_resolution.x / max(image_resolution.y, 1.0);
    var result = uv;
    if (screen_ratio > image_ratio) {
        let scale = screen_ratio / image_ratio;
        result.x = (uv.x - 0.5) * scale + 0.5;
    } else {
        let scale = image_ratio / screen_ratio;
        result.y = (uv.y - 0.5) * scale + 0.5;
    }
    return result;
}

fn stretch_uv(uv: vec2<f32>) -> vec2<f32> {
    return uv;
}

fn center_uv(uv: vec2<f32>, image_resolution: vec2<f32>, screen_resolution: vec2<f32>) -> vec2<f32> {
    let scale_x = screen_resolution.x / max(image_resolution.x, 1.0);
    let scale_y = screen_resolution.y / max(image_resolution.y, 1.0);
    let scale = min(scale_x, scale_y);
    let img_w = image_resolution.x * scale / screen_resolution.x;
    let img_h = image_resolution.y * scale / screen_resolution.y;
    let offset_x = (1.0 - img_w) * 0.5;
    let offset_y = (1.0 - img_h) * 0.5;
    let result = (uv - vec2<f32>(offset_x, offset_y)) / vec2<f32>(max(img_w, 0.001), max(img_h, 0.001));
    return result;
}

fn tile_uv(uv: vec2<f32>, image_resolution: vec2<f32>, screen_resolution: vec2<f32>) -> vec2<f32> {
    let scale_x = screen_resolution.x / max(image_resolution.x, 1.0);
    let scale_y = screen_resolution.y / max(image_resolution.y, 1.0);
    let tiled = uv * vec2<f32>(scale_x, scale_y);
    return fract(tiled);
}

fn scale_uv(uv: vec2<f32>, image_resolution: vec2<f32>, screen_resolution: vec2<f32>, mode: u32) -> vec2<f32> {
    if (mode == 1u) {
        return fit_uv(uv, image_resolution, screen_resolution);
    }
    if (mode == 2u) {
        return stretch_uv(uv);
    }
    if (mode == 3u) {
        return center_uv(uv, image_resolution, screen_resolution);
    }
    if (mode == 4u) {
        return tile_uv(uv, image_resolution, screen_resolution);
    }
    return cover_uv(uv, image_resolution, screen_resolution);
}

// ---------------------------------------------------------------------------
// Transition Geometry & Reveal Math
// ---------------------------------------------------------------------------

// Quintic smootherstep: zero edge velocity and acceleration for silky smooth edges
fn smootherstep(edge0: f32, edge1: f32, value: f32) -> f32 {
    let width = max(edge1 - edge0, 0.0001);
    let t = clamp((value - edge0) / width, 0.0, 1.0);
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

fn circular_distance(uv: vec2<f32>, origin: vec2<f32>, resolution: vec2<f32>) -> f32 {
    let aspect = resolution.x / max(resolution.y, 1.0);
    return distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(origin.x * aspect, origin.y));
}

fn circular_max_radius(origin: vec2<f32>, resolution: vec2<f32>) -> f32 {
    let aspect = resolution.x / max(resolution.y, 1.0);
    let far = vec2<f32>(
        select(0.0, aspect, origin.x < 0.5),
        select(0.0, 1.0, origin.y < 0.5)
    );
    return distance(far, vec2<f32>(origin.x * aspect, origin.y));
}

fn circular_reveal(
    uv: vec2<f32>,
    origin: vec2<f32>,
    resolution: vec2<f32>,
    progress: f32,
    feather: f32,
    edge_offset: f32,
) -> f32 {
    let max_radius = circular_max_radius(origin, resolution);
    let radius = progress * (max_radius + feather) + edge_offset;
    let distance_from_origin = circular_distance(uv, origin, resolution);
    return 1.0 - smootherstep(radius - feather, radius + feather, distance_from_origin);
}

fn circular_outer_reveal(
    uv: vec2<f32>,
    origin: vec2<f32>,
    resolution: vec2<f32>,
    progress: f32,
    feather: f32,
) -> f32 {
    let max_radius = circular_max_radius(origin, resolution);
    let radius = (1.0 - progress) * (max_radius + feather);
    let distance_from_origin = circular_distance(uv, origin, resolution);
    return smootherstep(radius - feather, radius + feather, distance_from_origin);
}

// Directional Linear Wipe: standard linear sweep matching awww / swww wipe
fn linear_wipe_reveal(
    uv: vec2<f32>,
    direction: vec2<f32>,
    progress: f32,
    feather: f32,
) -> f32 {
    let dir_len = length(direction);
    var d = vec2<f32>(1.0, 0.0);
    if (dir_len > 0.001) {
        d = direction / dir_len;
    }
    // Project UV onto the normalized direction vector.
    // Range of dot(uv - 0.5, d) is [-half_span, half_span].
    let half_span = 0.5 * (abs(d.x) + abs(d.y));
    let coord = dot(uv - vec2<f32>(0.5, 0.5), d);
    let f = max(feather, 0.005);
    // As progress goes from 0 to 1, threshold moves across the screen
    let min_pos = -half_span - f;
    let max_pos = half_span + f;
    let threshold = mix(min_pos, max_pos, progress);
    return smootherstep(threshold - f, threshold + f, coord);
}

// ---------------------------------------------------------------------------
// High-Quality Multi-ring Gaussian Blur (16 golden-ratio samples)
// ---------------------------------------------------------------------------
fn sample_gaussian_blur(
    tex: texture_2d<f32>,
    smp: sampler,
    uv: vec2<f32>,
    blur_px: f32,
    resolution: vec2<f32>,
) -> vec4<f32> {
    if (blur_px <= 0.05) {
        return textureSample(tex, smp, uv);
    }
    let aspect = resolution.x / max(resolution.y, 1.0);
    let texel_step = blur_px / max(min(resolution.x, resolution.y), 1.0);
    var acc = textureSample(tex, smp, uv) * 0.18;
    var total_weight = 0.18;

    // Golden angle distribution for uniform circular disk bokeh
    let golden_angle = 2.39996323; // radians
    for (var i = 1; i <= 15; i = i + 1) {
        let r = sqrt(f32(i) / 15.0);
        let theta = f32(i) * golden_angle;
        let weight = exp(-0.5 * (r * 2.0) * (r * 2.0));
        let offset = vec2<f32>(cos(theta) / aspect, sin(theta)) * (r * texel_step);
        acc = acc + textureSample(tex, smp, uv + offset) * weight;
        total_weight = total_weight + weight;
    }
    return acc / total_weight;
}

// ---------------------------------------------------------------------------
// Fragment Entry Point
// ---------------------------------------------------------------------------

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let uv = in.uv;
    let raw_p = clamp(uniforms.progress, 0.0, 1.0);
    let p = apply_easing(raw_p, uniforms.easing);

    let uv_old = scale_uv(uv, uniforms.old_image_resolution, uniforms.resolution, uniforms.scaling_mode);
    let uv_new = scale_uv(uv, uniforms.image_resolution, uniforms.resolution, uniforms.scaling_mode);

    // Exact endpoint frames guarantee zero blending artifacts at start/end
    if (uniforms.progress <= 0.0) {
        return textureSample(t_diffuse1, s_diffuse1, uv_old);
    }
    if (uniforms.progress >= 1.0) {
        return textureSample(t_diffuse2, s_diffuse2, uv_new);
    }

    // 0: Fade / Simple (pure smooth crossfade)
    if (uniforms.effect_type == 0u) {
        let color1 = textureSample(t_diffuse1, s_diffuse1, uv_old);
        let color2 = textureSample(t_diffuse2, s_diffuse2, uv_new);
        let opacity = mix(uniforms.param_a, uniforms.param_b, p);
        return mix(color1, color2, clamp(opacity, 0.0, 1.0));
    }

    // 1: Multi-ring Gaussian Blur crossfade
    else if (uniforms.effect_type == 1u) {
        let blur_px = max(mix(uniforms.param_a, uniforms.param_b, p), 0.0);
        let c1 = sample_gaussian_blur(t_diffuse1, s_diffuse1, uv_old, blur_px, uniforms.resolution);
        let c2 = sample_gaussian_blur(t_diffuse2, s_diffuse2, uv_new, blur_px, uniforms.resolution);
        return mix(c1, c2, p);
    }

    // 2: Directional Linear Wipe (awww / swww style linear angled sweep)
    else if (uniforms.effect_type == 2u) {
        let softness = clamp(max(uniforms.param_a, 0.04), 0.04, 0.25);
        let reveal = linear_wipe_reveal(uv, uniforms.direction, p, softness);
        let color1 = textureSample(t_diffuse1, s_diffuse1, uv_old);
        let color2 = textureSample(t_diffuse2, s_diffuse2, uv_new);
        return mix(color1, color2, reveal);
    }

    // 3: Slide (Smooth directional translation wipe without cropping artifacts)
    else if (uniforms.effect_type == 3u) {
        let softness = 0.08;
        let reveal = linear_wipe_reveal(uv, uniforms.direction, p, softness);
        let color1 = textureSample(t_diffuse1, s_diffuse1, uv_old);
        let color2 = textureSample(t_diffuse2, s_diffuse2, uv_new);
        return mix(color1, color2, reveal);
    }

    // 4: Zoom (subtle camera push focus crossfade)
    else if (uniforms.effect_type == 4u) {
        let zoom_scale = mix(uniforms.param_a, uniforms.param_b, p);
        let origin = uniforms.origin;
        let uv_zoom_old = (uv_old - origin) / max(zoom_scale, 0.1) + origin;
        let uv_zoom_new = (uv_new - origin) * max(mix(1.04, 1.0, p), 0.1) + origin;
        let color1 = textureSample(t_diffuse1, s_diffuse1, uv_zoom_old);
        let color2 = textureSample(t_diffuse2, s_diffuse2, uv_zoom_new);
        return mix(color1, color2, p);
    }

    // 5: Pixelate (smooth dynamic mosaic grid)
    else if (uniforms.effect_type == 5u) {
        let mosaic_size = mix(uniforms.param_a, uniforms.param_b, p);
        var uv_p_old = uv_old;
        var uv_p_new = uv_new;
        if (mosaic_size > 1.5) {
            let res = uniforms.resolution;
            let blocks_x = max(res.x / mosaic_size, 4.0);
            let blocks_y = max(res.y / mosaic_size, 4.0);
            let block = vec2<f32>(blocks_x, blocks_y);
            uv_p_old = floor(uv_old * block) / block;
            uv_p_new = floor(uv_new * block) / block;
        }
        let color1 = textureSample(t_diffuse1, s_diffuse1, uv_p_old);
        let color2 = textureSample(t_diffuse2, s_diffuse2, uv_p_new);
        return mix(color1, color2, p);
    }

    // 6: Liquid ripple reveal (organic surface tension wave)
    else if (uniforms.effect_type == 6u) {
        let origin = uniforms.origin;
        let dist = circular_distance(uv, origin, uniforms.resolution);
        let freq = max(uniforms.param_a, 0.1);
        let amp = max(uniforms.param_b, 0.0);
        let speed = max(uniforms.param_c, 0.0);
        let envelope = sin(raw_p * 3.14159265);
        let ripple = sin(dist * freq * 6.2831853 - raw_p * speed * 6.2831853) * amp * envelope;
        let reveal = circular_reveal(uv, origin, uniforms.resolution, p, 0.055, ripple);
        let color1 = textureSample(t_diffuse1, s_diffuse1, uv_old);
        let color2 = textureSample(t_diffuse2, s_diffuse2, uv_new);
        return mix(color1, color2, reveal);
    }

    // 7: Dissolve (cellular noise dissolve)
    else if (uniforms.effect_type == 7u) {
        let scale = uniforms.param_a;
        let softness = max(uniforms.param_b, 0.001);
        let dist = circular_distance(uv, uniforms.origin, uniforms.resolution);
        let rings = sin(dist * max(scale, 1.0) * 6.2831853) * softness * 0.5;
        let reveal = circular_reveal(uv, uniforms.origin, uniforms.resolution, p, max(softness, 0.065), rings);
        let color1 = textureSample(t_diffuse1, s_diffuse1, uv_old);
        let color2 = textureSample(t_diffuse2, s_diffuse2, uv_new);
        return mix(color1, color2, reveal);
    }

    // 8: Custom shader pass-through
    else if (uniforms.effect_type == 8u) {
        let color1 = textureSample(t_diffuse1, s_diffuse1, uv_old);
        let color2 = textureSample(t_diffuse2, s_diffuse2, uv_new);
        return mix(color1, color2, p);
    }

    // 9: Wave reveal (organic oscillating border)
    else if (uniforms.effect_type == 9u) {
        let wave_freq = max(uniforms.param_a, 0.1);
        let wave_amp = max(uniforms.param_b, 0.0);
        let dist = circular_distance(uv, uniforms.origin, uniforms.resolution);
        let envelope = sin(raw_p * 3.14159265);
        let wave = sin(dist * wave_freq * 6.2831853 - raw_p * 6.2831853) * wave_amp * envelope;
        let edge = circular_reveal(uv, uniforms.origin, uniforms.resolution, p, 0.065, wave);
        let color1 = textureSample(t_diffuse1, s_diffuse1, uv_old);
        let color2 = textureSample(t_diffuse2, s_diffuse2, uv_new);
        return mix(color1, color2, edge);
    }

    // 10: Grow / Center (expanding circle from origin, swww-style)
    else if (uniforms.effect_type == 10u) {
        let edge = circular_reveal(uv, uniforms.origin, uniforms.resolution, p, 0.065, 0.0);
        let color1 = textureSample(t_diffuse1, s_diffuse1, uv_old);
        let color2 = textureSample(t_diffuse2, s_diffuse2, uv_new);
        return mix(color1, color2, edge);
    }

    // 11: Outer (shrinking circle toward origin, swww-style)
    else if (uniforms.effect_type == 11u) {
        let edge = circular_outer_reveal(uv, uniforms.origin, uniforms.resolution, p, 0.065);
        let color1 = textureSample(t_diffuse1, s_diffuse1, uv_old);
        let color2 = textureSample(t_diffuse2, s_diffuse2, uv_new);
        return mix(color1, color2, edge);
    }

    return textureSample(t_diffuse1, s_diffuse1, uv_old);
}
