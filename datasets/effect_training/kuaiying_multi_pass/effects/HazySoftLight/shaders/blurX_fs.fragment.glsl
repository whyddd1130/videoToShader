#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform float u_sampleX;
uniform float u_sigmaX;
uniform float u_stepX;

float _f0(float _p0, float _p1)
{
    return exp((((-0.5) * _p0) * _p0) / (_p1 * _p1));
}

void main()
{
    if (u_sampleX < 9.9999997473787516355514526367188e-06)
    {
        gl_FragColor = texture2D(inputImageTexture, textureCoord);
        return;
    }
    float param = 0.0;
    float param_1 = u_sigmaX;
    float _58 = _f0(param, param_1);
    float _t1 = _58;
    vec4 _t2 = texture2D(inputImageTexture, textureCoord) * _58;
    vec2 _t3 = textureCoord;
    for (mediump int _t4 = 1; _t4 <= 1024; _t4++)
    {
        mediump float _80 = float(_t4);
        if (_80 > u_sampleX)
        {
            break;
        }
        float _91 = _80 * u_stepX;
        float param_2 = _91;
        float param_3 = u_sigmaX;
        float _97 = _f0(param_2, param_3);
        _t3.x = textureCoord.x - _91;
        if (_t3.x >= 0.0)
        {
            _t2 += (texture2D(inputImageTexture, _t3) * _97);
            _t1 += _97;
        }
        _t3.x = textureCoord.x + _91;
        if (_t3.x <= 1.0)
        {
            _t2 += (texture2D(inputImageTexture, _t3) * _97);
            _t1 += _97;
        }
    }
    vec4 _145 = _t2;
    vec4 _147 = _145 / vec4(_t1);
    _t2 = _147;
    gl_FragColor = _147;
}
