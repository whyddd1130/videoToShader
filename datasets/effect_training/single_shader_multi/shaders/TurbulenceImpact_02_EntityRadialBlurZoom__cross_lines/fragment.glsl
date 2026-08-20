precision highp float;

uniform float uProgress;
uniform float uTime;
precision highp int;
#define u_inverseGammaCorrection 0
#define u_gamma 1.0
#define u_intensity (0.05 + 2.8 * uProgress)
#define u_blurType 1
uniform sampler2D inputImageTexture;
#define u_center vec2(0.5, 0.5)
#define u_quality 0.35
#define u_sampleScale 64.0
#define u_sampleBias 8.0
#define u_weightDecay 0.965
#define u_normalizationSample 64.0
#define u_dither 0.0
#define u_borderType 0
#define u_blurAlpha 1
varying vec2 uv0;

vec4 _f1(mediump sampler2D _p0, vec2 _p1)
{
    vec4 _t0 = texture2D(_p0, _p1);
    if (u_inverseGammaCorrection == 1)
    {
        vec4 _68 = _t0;
        vec3 _74 = pow(_68.xyz, vec3(u_gamma));
        _t0.x = _74.x;
        _t0.y = _74.y;
        _t0.z = _74.z;
    }
    return _t0;
}

float _f2(float _p0, inout float _p1, float _p2, float _p3)
{
    _p1 = sign(_p1) * ((0.89999997615814208984375 * abs(_p1)) + 0.100000001490116119384765625);
    return ((_p2 * _p0) * _p1) + _p3;
}

float _f3(float _p0, float _p1, float _p2)
{
    return pow(pow(_p0, _p1), 1.0 / _p2);
}

float _f4(vec2 _p0)
{
    vec2 _119 = fract(_p0 * 13.5170001983642578125);
    vec2 _t1 = _119 + vec2(dot(_119, _119.yx + vec2(22.5410003662109375)));
    return fract((_t1.x + _t1.y) * _t1.y);
}

float _f0(inout float _p0)
{
    _p0 = abs(_p0);
    return abs((floor(ceil(_p0) / 2.0) * 2.0) - _p0);
}

void main()
{
    float _t2 = u_intensity;
    bool _147 = u_blurType == 2;
    if (_147)
    {
        _t2 *= 0.5;
    }
    vec2 param = uv0;
    vec4 _159 = _f1(inputImageTexture, param);
    vec4 _t3 = _159;
    float _t4 = 1.0;
    float _t5 = 1.0;
    vec4 _t6 = _159 * 1.0;
    vec2 _t7 = uv0;
    vec2 _176 = (uv0 - u_center) * _t2;
    float param_1 = u_quality;
    float param_2 = length(_176);
    float param_3 = u_sampleScale;
    float param_4 = u_sampleBias;
    float _192 = _f2(param_1, param_2, param_3, param_4);
    float _195 = min(_192, 128.0);
    vec2 _200 = _176 / vec2(_195);
    float param_5 = u_weightDecay;
    float param_6 = u_normalizationSample;
    float param_7 = _195;
    float _210 = _f3(param_5, param_6, param_7);
    if (u_dither > 9.9999997473787516355514526367188e-06)
    {
        vec2 param_8 = vec2(uv0);
        _t7 += (_200 * (u_dither * ((_f4(param_8) * 2.0) - 1.0)));
    }
    for (mediump int _t14 = 1; _t14 <= 128; _t14++)
    {
        mediump float _245 = float(_t14);
        if (_245 > _195)
        {
            break;
        }
        _t4 *= _210;
        vec2 _259 = _200 * _245;
        vec2 _t16 = _t7 - _259;
        bool _264 = _t16.x < 0.0;
        bool _271;
        if (!_264)
        {
            _271 = _t16.y < 0.0;
        }
        else
        {
            _271 = _264;
        }
        bool _278;
        if (!_271)
        {
            _278 = _t16.x > 1.0;
        }
        else
        {
            _278 = _271;
        }
        bool _285;
        if (!_278)
        {
            _285 = _t16.y > 1.0;
        }
        else
        {
            _285 = _278;
        }
        if (_285)
        {
            if (u_borderType == 0)
            {
                _t5 += _t4;
            }
            else
            {
                float param_9 = _t16.x;
                float _301 = _f0(param_9);
                _t16.x = _301;
                float param_10 = _t16.y;
                float _306 = _f0(param_10);
                _t16.y = _306;
                vec2 param_11 = _t16;
                _t6 += (_f1(inputImageTexture, param_11) * _t4);
                _t5 += _t4;
            }
        }
        else
        {
            vec2 param_12 = _t16;
            _t6 += (_f1(inputImageTexture, param_12) * _t4);
            _t5 += _t4;
        }
        if (_147)
        {
            _t16 = _t7 + _259;
            bool _340 = _t16.x < 0.0;
            bool _347;
            if (!_340)
            {
                _347 = _t16.y < 0.0;
            }
            else
            {
                _347 = _340;
            }
            bool _354;
            if (!_347)
            {
                _354 = _t16.x > 1.0;
            }
            else
            {
                _354 = _347;
            }
            bool _361;
            if (!_354)
            {
                _361 = _t16.y > 1.0;
            }
            else
            {
                _361 = _354;
            }
            if (_361)
            {
                if (u_borderType == 0)
                {
                    _t5 += _t4;
                }
                else
                {
                    float param_13 = _t16.x;
                    float _375 = _f0(param_13);
                    _t16.x = _375;
                    float param_14 = _t16.y;
                    float _380 = _f0(param_14);
                    _t16.y = _380;
                    vec2 param_15 = _t16;
                    _t6 += (_f1(inputImageTexture, param_15) * _t4);
                    _t5 += _t4;
                }
            }
            else
            {
                vec2 param_16 = _t16;
                _t6 += (_f1(inputImageTexture, param_16) * _t4);
                _t5 += _t4;
            }
        }
    }
    _t6 /= vec4(_t5);
    if (u_inverseGammaCorrection == 1)
    {
        vec4 _413 = _t6;
        vec3 _418 = pow(_413.xyz, vec3(1.0 / u_gamma));
        _t6.x = _418.x;
        _t6.y = _418.y;
        _t6.z = _418.z;
    }
    if (u_blurAlpha == 0)
    {
        _t6.w = _t3.w;
    }
    gl_FragColor = _t6;
}

