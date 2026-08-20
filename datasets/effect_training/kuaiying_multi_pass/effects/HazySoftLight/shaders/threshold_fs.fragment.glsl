#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform mediump int u_thresholdType;
uniform float u_thresholdLow;
uniform float u_thresholdHigh;
uniform float u_thresholdSmooth;
uniform float u_grayScale;

float _f3(inout float _p0, float _p1, float _p2)
{
    if ((_p0 <= _p1) || (_p0 > _p2))
    {
        _p0 = 0.0;
    }
    else
    {
        _p0 = (_p0 - _p1) / (1.0 - _p1);
    }
    return _p0;
}

vec4 _f4(inout vec4 _p0, float _p1, float _p2)
{
    float param = _p0.x;
    float param_1 = _p1;
    float param_2 = _p2;
    float _154 = _f3(param, param_1, param_2);
    float param_3 = _p0.y;
    float param_4 = _p1;
    float param_5 = _p2;
    float _163 = _f3(param_3, param_4, param_5);
    float param_6 = _p0.z;
    float param_7 = _p1;
    float param_8 = _p2;
    float _172 = _f3(param_6, param_7, param_8);
    float _180 = _p0.x;
    float _182 = _p0.y;
    float _185 = _p0.z;
    vec4 _190 = _p0;
    vec3 _192 = _190.xyz * (((_154 + _163) + _172) / max((_180 + _182) + _185, 9.9999997473787516355514526367188e-06));
    _p0.x = _192.x;
    _p0.y = _192.y;
    _p0.z = _192.z;
    return _p0;
}

float _f1(inout float _p0, float _p1, float _p2, float _p3)
{
    if (_p0 <= _p1)
    {
        _p0 = ((_p3 * _p0) * _p0) / max(_p1, 9.9999997473787516355514526367188e-06);
    }
    else
    {
        if (_p0 > _p2)
        {
            _p0 = _p3 * (((_p0 * _p0) - (_p2 * _p0)) + _p2);
        }
    }
    return _p0;
}

vec4 _f2(inout vec4 _p0, float _p1, float _p2, float _p3)
{
    float param = _p0.x;
    float param_1 = _p1;
    float param_2 = _p2;
    float param_3 = _p3;
    float _96 = _f1(param, param_1, param_2, param_3);
    _p0.x = _96;
    float param_4 = _p0.y;
    float param_5 = _p1;
    float param_6 = _p2;
    float param_7 = _p3;
    float _108 = _f1(param_4, param_5, param_6, param_7);
    _p0.y = _108;
    float param_8 = _p0.z;
    float param_9 = _p1;
    float param_10 = _p2;
    float param_11 = _p3;
    float _120 = _f1(param_8, param_9, param_10, param_11);
    _p0.z = _120;
    return _p0;
}

float _f0(vec3 _p0)
{
    return dot(_p0, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
}

void main()
{
    vec4 _t4 = texture2D(inputImageTexture, textureCoord);
    if (u_thresholdType == 0)
    {
        vec4 param = _t4;
        float param_1 = u_thresholdLow;
        float param_2 = u_thresholdHigh;
        vec4 _230 = _f4(param, param_1, param_2);
        _t4 = _230;
    }
    else
    {
        vec4 param_3 = _t4;
        float param_4 = u_thresholdLow;
        float param_5 = u_thresholdHigh;
        float param_6 = u_thresholdSmooth;
        vec4 _241 = _f2(param_3, param_4, param_5, param_6);
        _t4 = _241;
        vec3 param_7 = _241.xyz;
        vec4 _247 = _t4;
        vec3 _254 = mix(_247.xyz, vec3(_f0(param_7)), vec3(u_grayScale));
        _t4.x = _254.x;
        _t4.y = _254.y;
        _t4.z = _254.z;
    }
    gl_FragColor = _t4;
}
