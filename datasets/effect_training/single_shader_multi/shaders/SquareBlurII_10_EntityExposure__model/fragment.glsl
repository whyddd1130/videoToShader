precision highp float;

uniform float uProgress;
uniform float uTime;
precision highp int;
#define u_noUseLinearLight 0
#define u_gamma 1.0
uniform sampler2D inputImageTexture;
#define u_redExposure (0.2 + 1.8 * uProgress)
#define u_redOffset (0.0 + 0.18 * uProgress)
#define u_redGrayscaleCorrection 1.0
#define u_greenExposure (0.2 + 1.4 * uProgress)
#define u_greenOffset (0.0 + 0.12 * uProgress)
#define u_greenGrayscaleCorrection 1.0
#define u_blueExposure (0.2 + 1.2 * uProgress)
#define u_blueOffset (0.0 + 0.08 * uProgress)
#define u_blueGrayscaleCorrection 1.0
varying vec2 uv0;

float _f0(inout float _p0, float _p1, float _p2, float _p3)
{
    bool _21 = u_noUseLinearLight == 0;
    if (_21)
    {
        _p0 = pow(_p0, u_gamma);
    }
    _p0 *= pow(2.0, _p1);
    _p0 += _p2;
    _p0 = pow(_p0, 1.0 / _p3) * sign(_p0);
    if (_21)
    {
        _p0 = pow(_p0, 1.0 / u_gamma) * sign(_p0);
    }
    return _p0;
}

void main()
{
    vec4 _t0 = texture2D(inputImageTexture, uv0);
    float param = _t0.x;
    float param_1 = u_redExposure;
    float param_2 = u_redOffset;
    float param_3 = u_redGrayscaleCorrection;
    float _86 = _f0(param, param_1, param_2, param_3);
    _t0.x = _86;
    float param_4 = _t0.y;
    float param_5 = u_greenExposure;
    float param_6 = u_greenOffset;
    float param_7 = u_greenGrayscaleCorrection;
    float _101 = _f0(param_4, param_5, param_6, param_7);
    _t0.y = _101;
    float param_8 = _t0.z;
    float param_9 = u_blueExposure;
    float param_10 = u_blueOffset;
    float param_11 = u_blueGrayscaleCorrection;
    float _116 = _f0(param_8, param_9, param_10, param_11);
    _t0.z = _116;
    gl_FragColor = clamp(_t0, vec4(0.0), vec4(1.0));
}

