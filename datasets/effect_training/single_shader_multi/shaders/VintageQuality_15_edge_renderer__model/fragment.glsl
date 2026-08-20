precision highp float;

uniform float uProgress;
uniform float uTime;
precision highp int;
#define u_ScreenParams vec4(1080.0, 1080.0, 1.0/1080.0, 1.0/1080.0)
uniform mediump sampler2D inputImageTexture;
#define grayColor 1.0
#define lowerLimit (0.10 + 0.35 * uProgress)
#define upperLimit (0.35 + 0.55 * uProgress)
#define brightness (0.40 + 2.40 * uProgress)
varying vec2 v_uv;

void main()
{
    vec2 _t1 = vec2(1.0) / ((u_ScreenParams.xy / vec2(min(u_ScreenParams.x, u_ScreenParams.y))) * 720.0);
    mediump vec4 _55 = texture2D(inputImageTexture, v_uv + vec2((-1.0) * _t1.x, (-1.0) * _t1.y));
    mediump vec4 _70 = texture2D(inputImageTexture, v_uv + vec2((-1.0) * _t1.x, 0.0 * _t1.y));
    mediump vec4 _84 = texture2D(inputImageTexture, v_uv + vec2((-1.0) * _t1.x, 1.0 * _t1.y));
    mediump vec4 _98 = texture2D(inputImageTexture, v_uv + vec2(1.0 * _t1.x, (-1.0) * _t1.y));
    mediump vec4 _113 = texture2D(inputImageTexture, v_uv + vec2(1.0 * _t1.x, 0.0 * _t1.y));
    mediump vec4 _127 = texture2D(inputImageTexture, v_uv + vec2(1.0 * _t1.x, 1.0 * _t1.y));
    vec4 _130 = (((((vec4(0.0) + (_55 * (-1.0))) + (_70 * (-2.0))) + (_84 * (-1.0))) + (_98 * 1.0)) + (_113 * 2.0)) + (_127 * 1.0);
    vec4 _t2 = _130;
    mediump vec4 _142 = texture2D(inputImageTexture, v_uv + vec2((-1.0) * _t1.x, (-1.0) * _t1.y));
    mediump vec4 _156 = texture2D(inputImageTexture, v_uv + vec2(0.0 * _t1.x, (-1.0) * _t1.y));
    mediump vec4 _170 = texture2D(inputImageTexture, v_uv + vec2(1.0 * _t1.x, (-1.0) * _t1.y));
    mediump vec4 _184 = texture2D(inputImageTexture, v_uv + vec2((-1.0) * _t1.x, 1.0 * _t1.y));
    mediump vec4 _198 = texture2D(inputImageTexture, v_uv + vec2(0.0 * _t1.x, 1.0 * _t1.y));
    mediump vec4 _212 = texture2D(inputImageTexture, v_uv + vec2(1.0 * _t1.x, 1.0 * _t1.y));
    vec4 _215 = (((((vec4(0.0) + (_142 * (-1.0))) + (_156 * (-2.0))) + (_170 * (-1.0))) + (_184 * 1.0)) + (_198 * 2.0)) + (_212 * 1.0);
    vec4 _t3 = _215;
    vec4 _t4 = vec4(0.0);
    if (grayColor > 0.5)
    {
        float _237 = ((0.333000004291534423828125 * _t2.x) + (0.333000004291534423828125 * _t2.y)) + (0.333000004291534423828125 * _t2.z);
        float _249 = ((0.333000004291534423828125 * _t3.x) + (0.333000004291534423828125 * _t3.y)) + (0.333000004291534423828125 * _t3.z);
        _t4 = vec4((_237 * _237) + (_249 * _249));
    }
    else
    {
        _t4 = (_130 * _130) + (_215 * _215);
    }
    _t4 = smoothstep(vec4(lowerLimit), vec4(upperLimit), _t4 * brightness);
    _t4.w = texture2D(inputImageTexture, v_uv).w;
    gl_FragColor = _t4;
}

