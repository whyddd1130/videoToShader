precision highp float;

uniform float uProgress;
uniform float uTime;
precision highp int;

uniform sampler2D inputImageTexture;
#define u_offsetX (-0.08 + 0.16 * uProgress)
#define u_offsetY (0.08 - 0.16 * uProgress)
varying vec2 v_uv;

void main()
{
    vec4 _t0 = texture2D(inputImageTexture, v_uv);
    vec2 _34 = (vec2(u_offsetX, u_offsetY) * (vec2(1.0) - v_uv)) * v_uv;
    vec4 _t3 = texture2D(inputImageTexture, v_uv + _34);
    _t0.x = _t3.x;
    vec4 _t5 = texture2D(inputImageTexture, v_uv - _34);
    _t0.z = _t5.z;
    _t0.w = ((_t3.w + _t0.w) + _t5.w) / 3.0;
    gl_FragColor = _t0;
}

