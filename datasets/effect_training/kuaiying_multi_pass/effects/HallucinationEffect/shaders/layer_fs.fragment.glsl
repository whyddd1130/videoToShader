#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

uniform mediump sampler2D u_baseTexure;
uniform mediump sampler2D u_sourceTexture;
varying vec2 textureCoord;

uniform mediump int u_blendMode;
uniform mediump int u_layerType;
uniform float u_layerOpacity;
uniform mediump int u_hasBlend;
uniform mediump int u_hasBaseTexture;
uniform mediump int u_hasSourceTexture;
uniform mediump int u_hasTrs;
uniform mat4 u_mvMat;
uniform mat4 u_pMat;
uniform float u_mirrorEdge;
uniform float u_alpha;

vec4 _f7(vec3 _p0, vec3 _p1, vec3 _p2, vec3 _p3, vec3 _p4)
{
    vec3 _404 = _p3 - _p2;
    vec3 _408 = _p4 - _p2;
    vec3 _412 = cross(_p1, _408);
    float _416 = dot(_404, _412);
    if (_416 <= 1.0000000116860974230803549289703e-07)
    {
        return vec4(-1.0);
    }
    vec3 _428 = _p0 - _p2;
    float _434 = dot(_428, _412) / _416;
    if ((_434 < 0.0) || (_434 > 1.0))
    {
        return vec4(-1.0);
    }
    vec3 _446 = cross(_428, _404);
    float _452 = dot(_p1, _446) / _416;
    bool _454 = _452 < 0.0;
    bool _462;
    if (!_454)
    {
        _462 = (_434 + _452) > 1.0;
    }
    else
    {
        _462 = _454;
    }
    if (_462)
    {
        return vec4(-1.0);
    }
    return vec4(_434, _452, dot(_408, _446) / _416, 1.0);
}

vec2 _f8(mat4 _p0, mat4 _p1, vec2 _p2)
{
    vec4 _505 = _p1 * vec4((_p2 * 2.0) - vec2(1.0), 0.0, 1.0);
    vec4 _t16 = _505;
    vec3 _521 = normalize((_505.xyz / vec3(_t16.w)) - vec3(0.0));
    vec3 _524 = (_p0 * vec4(10.0, -10.0, 0.0, 1.0)).xyz;
    vec3 _527 = _524 + vec3(9.9999997473787516355514526367188e-06, 0.0, 0.0);
    vec3 _529 = (_p0 * vec4(-10.0, 10.0, 0.0, 1.0)).xyz;
    vec3 _531 = _529 + vec3(0.0, 9.9999997473787516355514526367188e-06, 0.0);
    vec3 param = vec3(0.0);
    vec3 param_1 = _521;
    vec3 _538 = (_p0 * vec4(-10.0, -10.0, 0.0, 1.0)).xyz;
    vec3 param_2 = _538;
    vec3 param_3 = _527;
    vec3 param_4 = _531;
    vec4 _t20 = _f7(param, param_1, param_2, param_3, param_4);
    vec3 _545 = _529 - vec3(9.9999997473787516355514526367188e-06, 0.0, 0.0);
    vec3 _548 = _524 - vec3(0.0, 9.9999997473787516355514526367188e-06, 0.0);
    vec3 param_5 = vec3(0.0);
    vec3 param_6 = _521;
    vec3 param_7 = _545;
    vec3 param_8 = _548;
    vec3 _557 = (_p0 * vec4(10.0, 10.0, 0.0, 1.0)).xyz;
    vec3 param_9 = _557;
    vec4 _t21 = _f7(param_5, param_6, param_7, param_8, param_9);
    vec3 param_10 = vec3(0.0);
    vec3 param_11 = _521;
    vec3 param_12 = _538;
    vec3 param_13 = _531;
    vec3 param_14 = _527;
    vec4 _t22 = _f7(param_10, param_11, param_12, param_13, param_14);
    vec3 param_15 = vec3(0.0);
    vec3 param_16 = _521;
    vec3 param_17 = _545;
    vec3 param_18 = _557;
    vec3 param_19 = _548;
    vec4 _t23 = _f7(param_15, param_16, param_17, param_18, param_19);
    vec2 _729 = (((((((vec2(-4.5) * ((1.0 - _t20.x) - _t20.y)) + (vec2(5.5, -4.5) * _t20.x)) + (vec2(-4.5, 5.5) * _t20.y)) * step(0.0, _t20.w)) + ((((vec2(-4.5, 5.5) * ((1.0 - _t21.x) - _t21.y)) + (vec2(5.5, -4.5) * _t21.x)) + (vec2(5.5) * _t21.y)) * (step(_t20.w, 0.0) * step(0.0, _t21.w)))) + ((((vec2(-4.5) * ((1.0 - _t22.x) - _t22.y)) + (vec2(-4.5, 5.5) * _t22.x)) + (vec2(5.5, -4.5) * _t22.y)) * ((step(_t20.w, 0.0) * step(_t21.w, 0.0)) * step(0.0, _t22.w)))) + ((((vec2(-4.5, 5.5) * ((1.0 - _t23.x) - _t23.y)) + (vec2(5.5) * _t23.x)) + (vec2(5.5, -4.5) * _t23.y)) * (((step(_t20.w, 0.0) * step(_t21.w, 0.0)) * step(_t22.w, 0.0)) * step(0.0, _t23.w)))) + (vec2(-10000.0) * (((step(_t20.w, 0.0) * step(_t21.w, 0.0)) * step(_t22.w, 0.0)) * step(_t23.w, 0.0)));
    return _729;
}

vec2 _f10(vec2 _p0)
{
    return abs(mod(_p0 - vec2(1.0), vec2(2.0)) - vec2(1.0));
}

float _f9(vec2 _p0)
{
    vec2 _t29 = step(vec2(0.0), _p0) * step(_p0, vec2(1.0));
    return _t29.x * _t29.y;
}

float _f5(vec3 _p0)
{
    return dot(_p0, vec3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
}

vec4 _f11(vec4 _p0)
{
    vec4 _t30 = vec4(0.0);
    float _t31 = _t30.w;
    return _p0 * _t31;
}

vec4 _f39(inout vec4 _p0, inout vec4 _p1)
{
    float _1392 = _p0.w;
    vec4 _1394 = _p0;
    vec3 _1397 = _1394.xyz / vec3(max(_1392, 9.9999997473787516355514526367188e-06));
    _p0.x = _1397.x;
    _p0.y = _1397.y;
    _p0.z = _1397.z;
    float _1405 = _p1.w;
    vec4 _1407 = _p1;
    vec3 _1410 = _1407.xyz / vec3(max(_1405, 9.9999997473787516355514526367188e-06));
    _p1.x = _1410.x;
    _p1.y = _1410.y;
    _p1.z = _1410.z;
    vec4 _t32 = _p1;
    if (u_blendMode == 1)
    {
        vec3 _1428 = _p0.xyz + _p1.xyz;
        _t32.x = _1428.x;
        _t32.y = _1428.y;
        _t32.z = _1428.z;
    }
    else
    {
        if (u_blendMode == 2)
        {
            vec3 _1444 = _p0.xyz * _p1.xyz;
            _t32.x = _1444.x;
            _t32.y = _1444.y;
            _t32.z = _1444.z;
        }
        else
        {
            if (u_blendMode == 3)
            {
                vec3 _1461 = abs(_p0.xyz - _p1.xyz);
                _t32.x = _1461.x;
                _t32.y = _1461.y;
                _t32.z = _1461.z;
            }
            else
            {
                _t32.x = _p0.xyz.x;
                _t32.y = _p0.xyz.y;
                _t32.z = _p0.xyz.z;
            }
        }
    }
    vec4 _t33 = vec4(0.0);
    if (u_layerType == 1)
    {
        float _t34 = 1.0;
        vec4 _2047 = mix(_p1, vec4(_t32.xyz, _p0.w), vec4(u_layerOpacity * _t34));
        _t33 = _2047;
        float _2049 = _t33.w;
        vec3 _2052 = _2047.xyz * _2049;
        _t33.x = _2052.x;
        _t33.y = _2052.y;
        _t33.z = _2052.z;
    }
    else
    {
        vec3 _2087 = (((_p1.xyz * _p1.w) * (1.0 - _p0.w)) + ((_p0.xyz * _p0.w) * (1.0 - _p1.w))) + (_t32.xyz * (_p0.w * _p1.w));
        _t33.x = _2087.x;
        _t33.y = _2087.y;
        _t33.z = _2087.z;
        _t33.w = _p0.w + (_p1.w * (1.0 - _p0.w));
    }
    return _t33;
}

void main()
{
    vec4 _t35 = vec4(0.0);
    bool _2110 = u_hasBlend == 1;
    if (_2110)
    {
        if (u_hasBaseTexture == 1)
        {
            _t35 = texture2D(u_baseTexure, textureCoord);
        }
        if (u_hasSourceTexture == 0)
        {
            gl_FragColor = _t35;
            return;
        }
    }
    vec4 _t36 = vec4(0.0);
    if (u_hasTrs == 1)
    {
        mat4 param = u_mvMat;
        mat4 param_1 = u_pMat;
        vec2 param_2 = textureCoord;
        vec2 _2148 = _f8(param, param_1, param_2);
        float _2151 = step(u_mirrorEdge, 0.5);
        vec2 param_3 = _2148;
        vec2 _2161 = (_2148 * _2151) + (_f10(param_3) * (1.0 - _2151));
        vec2 param_4 = _2161;
        _t36 = (texture2D(u_sourceTexture, _2161) * u_alpha) * _f9(param_4);
    }
    else
    {
        if (u_hasSourceTexture == 1)
        {
            _t36 = texture2D(u_sourceTexture, textureCoord);
        }
    }
    if (_2110)
    {
        vec4 param_6 = _t36;
        vec4 param_7 = _t35;
        vec4 _2199 = _f39(param_6, param_7);
        _t36 = _2199;
    }
    gl_FragColor = _t36;
}
