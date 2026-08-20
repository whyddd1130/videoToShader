#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform vec2 u_ScreenParams;
uniform mediump int u_inverseGammaCorrection;
uniform float u_gamma;
uniform float u_sampleX;
uniform float u_sigmaX;
uniform float u_spaceDither;
uniform float u_stepX;
uniform float u_stepY;
uniform mediump int u_borderType;
uniform mediump int u_blurAlpha;

vec4 _f2(mediump sampler2D _p0, vec2 _p1)
{
    vec4 _t3 = texture2D(_p0, _p1);
    if (u_inverseGammaCorrection == 1)
    {
        vec4 _105 = _t3;
        vec3 _111 = pow(_105.xyz, vec3(u_gamma));
        _t3.x = _111.x;
        _t3.y = _111.y;
        _t3.z = _111.z;
    }
    return _t3;
}

float _f1(float _p0, float _p1)
{
    return exp((((-0.5) * _p0) * _p0) / (_p1 * _p1));
}

float _f0(vec2 _p0)
{
    vec3 _46 = fract(vec3((_p0 * u_ScreenParams.xy).xyx) * 0.103100001811981201171875);
    vec3 _t1 = _46 + vec3(dot(_46, _46.yzx + vec3(33.3300018310546875)));
    return (fract(fract((_t1.x + _t1.y) * _t1.z)) * 2.0) - 1.0;
}

void main()
{
    if (u_sampleX < 9.9999997473787516355514526367188e-06)
    {
        gl_FragColor = texture2D(inputImageTexture, textureCoord);
        return;
    }
    vec2 param = textureCoord;
    vec4 _139 = _f2(inputImageTexture, param);
    vec4 _t4 = _139;
    float param_1 = 0.0;
    float param_2 = u_sigmaX;
    float _146 = _f1(param_1, param_2);
    float _t5 = _146;
    vec4 _t6 = _139 * _146;
    vec2 _t7 = textureCoord;
    if (u_spaceDither > 9.9999997473787516355514526367188e-06)
    {
        vec2 param_3 = textureCoord;
        _t7 += (vec2(u_stepX, u_stepY) * (u_spaceDither * _f0(param_3)));
    }
    vec2 _t9 = _t7;
    for (mediump int _t10 = 1; _t10 <= 1024; _t10++)
    {
        mediump float _187 = float(_t10);
        if (_187 > u_sampleX)
        {
            break;
        }
        float _197 = _187 * u_stepX;
        float param_4 = _197;
        float param_5 = u_sigmaX;
        float _203 = _f1(param_4, param_5);
        _t9.x = _t7.x - _197;
        if (_t9.x < 0.0)
        {
            if (u_borderType == 1)
            {
                _t9.x = 0.0;
                vec2 param_6 = _t9;
                _t6 += (_f2(inputImageTexture, param_6) * _203);
                _t5 += _203;
            }
            else
            {
                if (u_borderType == 2)
                {
                    _t5 += _203;
                }
                else
                {
                    if (u_borderType == 3)
                    {
                        _t9.x = -_t9.x;
                        vec2 param_7 = _t9;
                        _t6 += (_f2(inputImageTexture, param_7) * _203);
                        _t5 += _203;
                    }
                }
            }
        }
        else
        {
            vec2 param_8 = _t9;
            _t6 += (_f2(inputImageTexture, param_8) * _203);
            _t5 += _203;
        }
        _t9.x = _t7.x + _197;
        if (_t9.x > 1.0)
        {
            if (u_borderType == 1)
            {
                _t9.x = 1.0;
                vec2 param_9 = _t9;
                _t6 += (_f2(inputImageTexture, param_9) * _203);
                _t5 += _203;
            }
            else
            {
                if (u_borderType == 2)
                {
                    _t5 += _203;
                }
                else
                {
                    if (u_borderType == 3)
                    {
                        _t9.x = 2.0 - _t9.x;
                        vec2 param_10 = _t9;
                        _t6 += (_f2(inputImageTexture, param_10) * _203);
                        _t5 += _203;
                    }
                }
            }
        }
        else
        {
            vec2 param_11 = _t9;
            _t6 += (_f2(inputImageTexture, param_11) * _203);
            _t5 += _203;
        }
    }
    _t6 /= vec4(_t5);
    if (u_inverseGammaCorrection == 1)
    {
        vec4 _343 = _t6;
        vec3 _348 = pow(_343.xyz, vec3(1.0 / u_gamma));
        _t6.x = _348.x;
        _t6.y = _348.y;
        _t6.z = _348.z;
    }
    if (u_blurAlpha == 0)
    {
        _t6.w = _t4.w;
    }
    gl_FragColor = _t6;
}
