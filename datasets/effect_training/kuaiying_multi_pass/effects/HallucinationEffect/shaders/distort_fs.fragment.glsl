#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform mediump sampler2D u_map;

uniform mediump int u_wrapModeX;
uniform mediump int u_wrapModeY;
uniform float u_distortScale;
uniform vec2 u_ScreenParams;
uniform float u_direction;
uniform mediump int u_steps;
uniform float u_warpRed;
uniform float u_warpBlue;
uniform float u_amountRelX;
uniform float u_amountRelY;
uniform vec3 u_color1;
uniform vec3 u_color2;
uniform vec3 u_color3;
uniform float u_mix;

float unpack(vec4 rgba)
{
    return rgba.x + rgba.y / 255.0 + rgba.z / 65025.0 + rgba.w / 16581375.0;
}

vec2 wrap(vec2 uv, int modeX, int modeY, vec2 bound)
{
    if (modeX == 0) uv.x = clamp(uv.x, 0.0, 1.0);
    else if (modeX == 1) uv.x = mod(uv.x, bound.x);
    else if (modeX == 2) uv.x = 1.0 - abs(mod(uv.x, bound.x) - 1.0);

    if (modeY == 0) uv.y = clamp(uv.y, 0.0, 1.0);
    else if (modeY == 1) uv.y = mod(uv.y, bound.y);
    else if (modeY == 2) uv.y = 1.0 - abs(mod(uv.y, bound.y) - 1.0);

    return uv;
}

vec4 sampleWrapped(sampler2D tex, inout vec2 uv)
{
    uv = wrap(uv, u_wrapModeX, u_wrapModeY, vec2(1.0));
    return texture2D(tex, uv);
}

vec3 gradient(vec3 a, vec3 b, vec3 c, float t)
{
    vec3 g;
    if (t < 0.5)
    {
        float s = t * 4.0;
        g = a * clamp(2.0 - s, 0.0, 1.0) + b * clamp(s, 0.0, 1.0);
    }
    else
    {
        float s = (t - 0.5) * 4.0;
        g = b * clamp(2.0 - s, 0.0, 1.0) + c * clamp(s, 0.0, 1.0);
    }
    return g;
}

void main()
{
    vec2 scale = vec2(u_distortScale) / ((u_ScreenParams.xy / min(u_ScreenParams.x, u_ScreenParams.y)) * 1080.0);
    vec2 dx = vec2(1.0, 0.0) * scale;
    vec2 dy = vec2(0.0, 1.0) * scale;

    vec4 s0 = texture2D(u_map, textureCoord + dx);
    vec4 s1 = texture2D(u_map, textureCoord - dx);
    vec4 s2 = texture2D(u_map, textureCoord + dy);
    vec4 s3 = texture2D(u_map, textureCoord - dy);

    vec2 grad = vec2(unpack(s0) - unpack(s1), unpack(s2) - unpack(s3));

    float angle = u_direction * 2.0 * 3.14159;
    mat2 rot = mat2(cos(angle), -sin(angle), sin(angle), cos(angle));

    vec4 accColor = vec4(0.0);
    vec4 accWeight = vec4(0.0);

    for (int i = 0; i < 100; ++i)
    {
        if (i >= u_steps) break;
        float t = float(i) / float(u_steps);
        vec2 offset = grad * mix(u_warpRed, u_warpBlue, t) * rot * vec2(u_amountRelX, u_amountRelY);
        vec2 uv = textureCoord + offset;
        vec4 col = sampleWrapped(inputImageTexture, uv);
        vec3 g = gradient(vec3(1,0,0), vec3(0,1,0), vec3(0,0,1), t);
        vec4 w = vec4(g, 1.0);
        accColor += col * w;
        accWeight += w;
    }

    vec4 outColor = accColor / accWeight;
    vec3 tint = (u_color1 + u_color2) + u_color3;
    gl_FragColor = mix(outColor, vec4(outColor.rgb * tint, outColor.a), u_mix);
}
