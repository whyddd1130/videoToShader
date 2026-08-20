#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform float u_stride;
uniform float u_angle;
uniform vec2 u_ScreenParams;
uniform mediump int u_steps;

float gaussian(float x)
{
    return exp(-0.5 * x * x / 0.09);
}

float unpack(vec4 rgba)
{
    return rgba.x + rgba.y / 255.0 + rgba.z / 65025.0 + rgba.w / 16581375.0;
}

vec3 blur(int steps, vec2 dir)
{
    float sum = 0.0;
    float weight = 0.0;
    for (int i = 0; i < 1000; ++i)
    {
        if (i >= steps) break;
        float t = float(i) / float(steps);
        float w = gaussian(t);
        vec4 a = texture2D(inputImageTexture, textureCoord + dir * float(i) * u_stride);
        vec4 b = texture2D(inputImageTexture, textureCoord - dir * float(i) * u_stride);
        sum += (unpack(a) + unpack(b)) * w * 0.5;
        weight += w;
    }
    return vec3(sum / weight);
}

vec4 pack(inout float v)
{
    vec4 rgba;
    v *= 255.0;
    rgba.x = floor(v) / 255.0;
    v = fract(v);
    v *= 255.0;
    rgba.y = floor(v) / 255.0;
    v = fract(v);
    v *= 255.0;
    rgba.z = floor(v) / 255.0;
    v = fract(v);
    rgba.w = v;
    return rgba;
}

void main()
{
    float rad = u_angle / 180.0 * 3.1415925;
    vec2 dir = vec2(cos(rad), sin(rad)) / ((u_ScreenParams.xy * 720.0) / min(u_ScreenParams.x, u_ScreenParams.y));
    vec3 g = blur(u_steps, dir);
    float v = g.x;
    gl_FragColor = pack(v);
}
