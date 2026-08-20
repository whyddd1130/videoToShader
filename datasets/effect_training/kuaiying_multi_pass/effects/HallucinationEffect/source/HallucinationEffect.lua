
local function newObject(o, class)
    class.__index = class
    return setmetatable(o, class)
end

---@language GLSL
local vs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

attribute vec2 position;
varying vec2 textureCoord;

void main()
{
    textureCoord = position * 0.5 + 0.5;
    gl_Position = vec4(position, 0.0, 1.0);
}
]]

---@language GLSL
local fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

void main() 
{
    gl_FragColor = texture2D(inputImageTexture, textureCoord);
}
]]

---@language GLSL
local layer_fs = [[
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
]]

---@language GLSL
local grayscale_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

vec3 grayscaleMix(vec3 color, float strength)
{
    float gray = dot(color, vec3(0.299, 0.587, 0.114));
    return mix(color, vec3(gray), strength);
}

vec4 grayscaleMixRGBA(vec4 rgba, float strength)
{
    return vec4(grayscaleMix(rgba.rgb, strength), rgba.a);
}

vec4 unpackFloatToRGBA(inout float value)
{
    vec4 rgba;
    value *= 255.0;
    rgba.r = floor(value) * (1.0 / 255.0);
    value = fract(value);
    value *= 255.0;
    rgba.g = floor(value) * (1.0 / 255.0);
    value = fract(value);
    value *= 255.0;
    rgba.b = floor(value) * (1.0 / 255.0);
    value = fract(value);
    rgba.a = value;
    return rgba;
}

void main()
{
    vec4 srcColor = texture2D(inputImageTexture, textureCoord);
    vec4 grayColor = grayscaleMixRGBA(srcColor, 1.0);
    float packedValue = grayColor.r;
    vec4 finalColor = unpackFloatToRGBA(packedValue);
    gl_FragColor = finalColor;
}
]]

---@language GLSL
local blur_fs = [[
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
]]

---@language GLSL
local distort_fs = [[
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
]]

---@language GLSL
local gauss_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform float u_sample;
uniform float u_baseTexWidth;
uniform float u_baseTexHeight;
uniform vec2 blurDir;

float normpdf(in float x, in float sigma)
{
    return 0.39894 * exp(-0.5 * x * x / (sigma * sigma)) / sigma;
}
vec4 gaussianBlur(sampler2D i_InputTex, vec2 i_Uv, vec2 i_Dir, vec2 screenSize)
{
    float sigma = 4.0;
    float weight = normpdf(0.0, sigma);

    vec4 sum = vec4(0.0);
    vec4 result = vec4(0.0);
    vec2 unit_uv = i_Dir / screenSize;
    float gamma = 1.0;
    vec4 curColor = texture2D(i_InputTex, i_Uv);
    vec4 centerPixel = pow(curColor, vec4(gamma)) * weight;
    float sum_weight = weight;

    float s = u_sample;
    for (int i = 1; i <= 1024; i++) {
        if (float(i) > u_sample) {
            break;
        }
        vec2 curRightCoordinate = i_Uv + float(i) * unit_uv;
        vec2 curLeftCoordinate = i_Uv + float(-i) * unit_uv;
        vec4 rightColor = texture2D(i_InputTex, curRightCoordinate);
        vec4 leftColor = texture2D(i_InputTex, curLeftCoordinate);
        weight = normpdf(float(i) / s * 15.0, sigma);
        sum += pow(rightColor, vec4(gamma)) * weight;
        sum += pow(leftColor, vec4(gamma)) * weight;
        sum_weight += weight * 2.0;
    }

    result = (sum + centerPixel) / sum_weight;
    result = pow(result, vec4(1.0 / gamma));
    return clamp(result, 0.0, 1.0);
}
void main()
{
    vec2 screenSize = vec2(u_baseTexWidth, u_baseTexHeight) / min(u_baseTexWidth, u_baseTexHeight) * 720.;
    gl_FragColor = gaussianBlur(inputImageTexture, textureCoord, blurDir, screenSize);
}
]]

---@language GLSL
local bokeh_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform float u_baseTexWidth;
uniform float u_baseTexHeight;
uniform float u_blurSize;
uniform float u_lightIns;
uniform float u_intensity;
uniform float u_regionIns;
uniform float u_quality;
uniform float u_scaleX;
uniform float u_scaleY;

mat2 rotate2d(in float angle)
{
    float s = sin(angle);
    float c = cos(angle);
    return mat2(c, -s, s, c);
}

float sdf(vec2 uv)
{
    vec2 newUV = uv;

    return step(dot(newUV, newUV), 121.);
}
vec2 flipUV(vec2 uv)
{
    return abs(mod(uv + 1., 2.) - 1.0);
}

vec4 blur(sampler2D inputTexture, vec2 textureCoordinate, float blurSize, vec2 screenSize)
{
    if (u_intensity < 0.01) {
        return texture2D(inputTexture, textureCoordinate);
    }
    float amount = 539.45;
    vec4 oriCol = vec4(0.);
    vec4 maxCol = oriCol;
    vec4 bokeh = pow(oriCol, vec4(9.0)) * amount + .4;
    vec4 sumCol = vec4(0.);
    vec4 sumWeight = bokeh;
    vec2 unitUV = vec2(2., 2.) * vec2(u_scaleX, u_scaleY) * vec2(blurSize) / screenSize;

    float blurStep = mix(2.0, 0.5, u_intensity) * mix(2., 1.0, u_quality);
    float blurRadius = 12. / blurStep * mix(0.6, 1.0, u_quality);
    blurRadius = max(5., blurRadius);
    float maxRegionIns = mix(0.7, 1.0, u_regionIns);
    for (float i = 0.; i < 30.; i++) {
        if (i > blurRadius || u_intensity < 0.3) {
            break;
        }
        for (float j = 0.; j < 30.; j++) {
            if (j > blurRadius) {
                break;
            }
            vec2 tempVec = vec2(mix(-11., 11., i / blurRadius), mix(-11., 11., j / blurRadius));
            if (sdf(tempVec) < 0.5) {
                continue;
            }
            vec4 tempCol = texture2D(inputTexture, (textureCoordinate - 0.5 * tempVec * unitUV));
            maxCol = max(maxCol, tempCol * maxRegionIns);
            bokeh = pow(tempCol, vec4(9.0)) * amount + .4;
            bokeh *= u_regionIns;
            sumCol += bokeh * tempCol;
            sumWeight += bokeh;
        }
    }

    float circleRadius = 34. / blurStep * mix(0.5, 1.0, clamp(u_quality * 1.5, 0.0 ,1.0));
    circleRadius = max(15.,circleRadius);
    mat2 rotmat = rotate2d(6.28 / circleRadius);
    vec2 tempVec = vec2(11, 0);
    for (float i = 0.; i < 70.; i++) {
        if (i > circleRadius) {
            break;
        }
        tempVec *= rotmat;
        vec4 tempCol = texture2D(inputTexture, (textureCoordinate - 0.5 * tempVec * unitUV));
        maxCol = max(maxCol, tempCol);
        bokeh = pow(tempCol, vec4(9.0)) * amount + .4;
        sumCol += bokeh * tempCol;
        sumWeight += bokeh;
    }

    vec4 resultCol = clamp(sumCol / sumWeight, 0., 1.);
    return vec4(mix(resultCol, maxCol, clamp(resultCol * u_lightIns, 0.0, 1.0)));
}

void main()
{
    vec2 screenSize = vec2(u_baseTexWidth, u_baseTexHeight) / min(u_baseTexWidth, u_baseTexHeight) * 720.;
    gl_FragColor = blur(inputImageTexture, textureCoord, u_blurSize, screenSize);
}
]]

---@language GLSL
local shadow_highlight_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform float u_highlightParam;
uniform float u_shadowParam;

vec3 highlight(vec3 rgb, float p)
{
    vec3 inv = vec3(1.0) - rgb;
    vec3 sqr = inv * inv;
    return (vec3(1.0) - pow(inv, vec3(p))) - ((sqr - sqr * inv) * (p - 1.0));
}

vec3 shadow(vec3 rgb, float p)
{
    vec3 sqr = rgb * rgb;
    return pow(rgb, vec3(p)) + ((sqr - sqr * rgb) * (p - 1.0));
}

void main()
{
    vec4 src = texture2D(inputImageTexture, textureCoord);
    vec4 outColor = src;
    outColor.rgb = highlight(outColor.rgb, u_highlightParam);
    outColor.rgb = shadow(outColor.rgb, u_shadowParam);
    gl_FragColor = clamp(outColor, vec4(0.0), vec4(1.0));
}
]]

---@language GLSL
local temperature_tone_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform vec3 u_redVec3;
uniform vec3 u_greenVec3;
uniform vec3 u_blueVec3;

void main()
{
    vec4 src = texture2D(inputImageTexture, textureCoord);
    vec4 outColor = src;
    outColor.r = dot(src.rgb, u_redVec3);
    outColor.g = dot(src.rgb, u_greenVec3);
    outColor.b = dot(src.rgb, u_blueVec3);
    gl_FragColor = clamp(outColor, vec4(0.0), vec4(1.0));
}
]]

local ae_keyframes = {
    ["LumiLayer_103-trs#position#vector"] =
{
	{
		{0.166667, 0, 0.666667, 1, }, 
		{0.3, 0.8, }, 
		{{542, 640, 0, }, {640, 640, 0, }, {542, 640, 0, }, {638.15734577179, 641.223819851875, 0, }, }, 
		{6413, }, 
		{0, }, 
	}, 
},
    ["LumiLayer_102-trs-blend#position#vector"] =
{
	{
		{0.988796, 0.019385, 0.666667, 1, }, 
		{0.2, 0.9, }, 
		{{640, 640, 0, }, {815, 640, 0, }, {669.166666030884, 640, 0, }, {785.833333969116, 640, 0, }, }, 
		{6413, }, 
		{0, }, 
	}, 
},
    ["LumiLayer_102-trs-blend#opacity#number"] =
{
	{
		{0.33333333, 0, 0.33197612, 1.001607186, }, 
		{0.133333, 0.733333, }, 
		{{100, }, {0, }, }, 
		{6417, }, 
		{0, }, 
	}, 
},
    ["LumiDistortChroma_101-effect0#distortScale#number"] =
{
	{
		{0.437643923, -0.001795865, 0.756827153, 0.778452699, }, 
		{0, 0.233333, }, 
		{{0, }, {1.5, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.574438426, -1.345765321, 0, 0.987808442, }, 
		{0.233333, 0.833333, }, 
		{{1.5, }, {0, }, }, 
		{6417, }, 
		{0, }, 
	}, 
},
    ["LumiDistortChroma_101-effect0#direction#number"] =
{
	{
		{0.166666667, 0.166666667, 0.66666667, 1, }, 
		{0, 0.233333, }, 
		{{0, }, {-0.9, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.410563859, 0.00436943, 0.735451115, 0.864778958, }, 
		{0.233333, 0.5, }, 
		{{-0.9, }, {-0.252858, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.491786287, 0.884587644, 0.739063998, 0.982292943, }, 
		{0.5, 0.866667, }, 
		{{-0.252858, }, {0, }, }, 
		{6417, }, 
		{0, }, 
	}, 
},
    ["LumiDistortChroma_101-effect0#blurMap#number"] =
{
	{
		{0.158311975, 0.088174704, 0.062052427, 0.824976682, }, 
		{0, 0.233333, }, 
		{{620, }, {110, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.257205374, 1.118972723, 0.583539377, 1.029240309, }, 
		{0.233333, 0.5, }, 
		{{110, }, {85, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.59989349, 0.201250796, 0.786921971, 0.766883078, }, 
		{0.5, 0.866667, }, 
		{{85, }, {625.091718, }, }, 
		{6417, }, 
		{0, }, 
	}, 
},
    ["LumiDistortChroma_101-effect0#warpRed#number"] =
{
	{
		{0.166666667, 0.166666667, 0.66666667, 1, }, 
		{0.233333, 0.5, }, 
		{{0.58, }, {0.102857, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.33333333, 0, 0.66666667, 1, }, 
		{0.5, 0.866667, }, 
		{{0.102857, }, {1.17, }, }, 
		{6417, }, 
		{0, }, 
	}, 
},
    ["LumiDistortChroma_101-effect0#amountRelX#number"] =
{
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0.233333, 0.5, }, 
		{{1, }, {2.09, }, }, 
		{6417, }, 
		{1, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0.5, 0.866667, }, 
		{{2.09, }, {1, }, }, 
		{6417, }, 
		{1, }, 
	}, 
},
    ["LumiBokehBlur_101-effect1#sample#number"] =
{
	{
		{0.3712154, 0, 0.565326372, 0.897404723, }, 
		{0, 0.233333, }, 
		{{0, }, {4.9, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.283856757, -0.312658395, 0.66666667, 1, }, 
		{0.233333, 0.5, }, 
		{{4.9, }, {3.7, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.33333333, 0, 0, 1, }, 
		{0.5, 0.633333, }, 
		{{3.7, }, {7.3, }, }, 
		{6417, }, 
		{0, }, 
	}, 
	{
		{0.33333333, 0, 0.266776291, 0.997078265, }, 
		{0.633333, 0.8, }, 
		{{7.3, }, {0, }, }, 
		{6417, }, 
		{0, }, 
	}, 
},
    ["LumiShadowHighlight_101-effect2#highlightIntensity#number"] =
{
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0.1, 0.5, }, 
		{{0, }, {0.14, }, }, 
		{6417, }, 
		{1, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0.5, 0.866667, }, 
		{{0.14, }, {0, }, }, 
		{6417, }, 
		{1, }, 
	}, 
},
    ["LumiTemperatureTone_101-effect3#temperatureIntensity#number"] =
{
	{
		{0.166666667, 0.166666667, 0.833333333, 0.833333333, }, 
		{0.1, 0.366667, }, 
		{{0, }, {0.28, }, }, 
		{6417, }, 
		{1, }, 
	}, 
	{
		{0.166666667, 0.166666667, 0.66666667, 1, }, 
		{0.366667, 0.866667, }, 
		{{0.28, }, {0, }, }, 
		{6417, }, 
		{0, }, 
	}, 
},
}

local AETools = AETools or {}
AETools.__index = AETools

local ThreeD_SPATIAL = 6413
local TwoD_SPATIAL = 6415

local function deepcopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
    else
        copy = orig
    end
    return copy
end

function AETools.new(attrs)
    if attrs == nil then return nil end

    local self = setmetatable({}, AETools)
    self.attrs = attrs

    local max_frame = 0
    local min_frame = 100000
    for _,v in pairs(attrs) do
        for i = 1, #v do
            local content = v[i]
            local cur_frame_min = content[2][1]
            local cur_frame_max = content[2][2]
            max_frame = math.max(cur_frame_max, max_frame)
            min_frame = math.min(cur_frame_min, min_frame)

            if  content[4] ~= nil
            and content[5] ~= nil
            and (content[4][1] == ThreeD_SPATIAL or content[4][1] == TwoD_SPATIAL)
            and content[5][1] == 0
            then
                local p0 = content[3][1]
                local totalLen = 0
                local lenInfo = {}
                lenInfo[0] = 0
                for test=1,200,1 do
                    local coord = self._cubicBezier3D(content[3][1], content[3][3], content[3][4], content[3][2], test/200)
                    local length = 0
                    if #p0 >= 3 then
                        length = math.sqrt((coord[1]-p0[1])*(coord[1]-p0[1])+(coord[2]-p0[2])*(coord[2]-p0[2])+(coord[3]-p0[3])*(coord[3]-p0[3]))
                    else
                        length = math.sqrt((coord[1]-p0[1])*(coord[1]-p0[1])+(coord[2]-p0[2])*(coord[2]-p0[2]))
                    end
                    p0 = coord
                    totalLen = totalLen + length
                    lenInfo[test] = totalLen
                end
                for test=1,200,1 do
                    lenInfo[test] = lenInfo[test]/(lenInfo[200]+0.000001)
                end
                content['lenInfo'] = lenInfo
            end
        end
    end

    self.all_frame = max_frame - min_frame
    self.min_frame = min_frame

    return self
end

function AETools:CurFrame(_p)
    local frame = math.floor(_p*self.all_frame)
    return frame + self.min_frame
end

function AETools:AllFrame(_p)
    return self.all_frame
end

function AETools._remap01(a,b,x)
    if x < a then return 0 end
    if x > b then return 1 end
    return (x-a)/(b-a)
end

function AETools._cubicBezier(p1, p2, p3, p4, t)
    local t2 = t * t
    local t3 = t2 * t
    local _t = 1 - t
    local _t2 = _t * _t
    local _t3 = _t2 * _t
    return {
        p1[1] * _t3 + 3 * p2[1] * _t2 * t + 3 * p3[1] * _t * t2 + p4[1] * t3,
        p1[2] * _t3 + 3 * p2[2] * _t2 * t + 3 * p3[2] * _t * t2 + p4[2] * t3,
    }
end

function AETools._cubicBezier3D(p1, p2, p3, p4, t)
    local t2 = t * t
    local t3 = t2 * t
    local _t = 1 - t
    local _t2 = _t * _t
    local _t3 = _t2 * _t
    local value = {
        p1[1] * _t3 + 3 * p2[1] * _t2 * t + 3 * p3[1] * _t * t2 + p4[1] * t3,
        p1[2] * _t3 + 3 * p2[2] * _t2 * t + 3 * p3[2] * _t * t2 + p4[2] * t3,
        0,
    }
    if #p1 >= 3 then
        value[3] = p1[3] * _t3 + 3 * p2[3] * _t2 * t + 3 * p3[3] * _t * t2 + p4[3] * t3
    end
    return value
end

function AETools:_cubicBezierSpatial(lenInfo, p1, p2, p3, p4, t)
    local p = 0
    if t <= 0 then
        p = 0
    elseif t >= 1 then
        p = 1
    else
        local ts = 199
        local te = 200
        for i=1,200,1 do
            if lenInfo[i] >= t then
                te = i
                ts = i-1
                break
            end
        end
        p = ts/200. + 0.005*(t-lenInfo[ts])/(lenInfo[te]-lenInfo[ts]+0.000001)
    end
    return self._cubicBezier3D(p1, p2, p3, p4, p)
end

function AETools:_cubicBezier01(_bezier_val, p, y_len)
    local x = self:_getBezier01X(_bezier_val, p, y_len)
    return self._cubicBezier(
        {0,0},
        {_bezier_val[1], _bezier_val[2]},
        {_bezier_val[3], _bezier_val[4]},
        {1, y_len},
        x
    )[2]
end

function AETools:AllFrame()
    return self.all_frame
end

function AETools:_getBezier01X(_bezier_val, x, y_len)
    local ts = 0
    local te = 1
    -- divide and conque
    local times = 1
    repeat
        local tm = (ts+te)*0.5
        local value = self._cubicBezier(
            {0,0},
            {_bezier_val[1], _bezier_val[2]},
            {_bezier_val[3], _bezier_val[4]},
            {1, y_len},
            tm)
        if(value[1]>x) then
            te = tm
        else
            ts = tm
        end
        times = times +1
    until(te-ts < 0.001 and times < 50)

    return (te+ts)*0.5
end

function AETools._mix(a, b, x, type)
    if type == 1 then
        return a * (1-x) + b * x
    end
    return a + x
end

function AETools:GetVal(_name, _progress)
    local content = self.attrs[_name]
    if content == nil then
        return nil
    end

    local cur_frame = _progress

    for i = 1, #content do
        local info = content[i]
        local start_frame = info[2][1]
        local end_frame = info[2][2]
        if cur_frame >= start_frame and cur_frame < end_frame then
            local cur_progress = self._remap01(start_frame, end_frame, cur_frame)
            local bezier = info[1]
            local value_range = info[3]
            local y_len = 1
            if (value_range[2][1] == value_range[1][1] and info[5] and info[5][1]==0 and #(value_range[1])==1) then
                y_len = 0
            end

            if info[5] and info[5][1] == 2 then
                return deepcopy(info[3][1])
            end

            if #bezier > 4 then
                local res = {}
                for k = 1, 3 do
                    local cur_bezier = {bezier[k], bezier[k+3], bezier[k+3*2], bezier[k+3*3]}
                    local p = self:_cubicBezier01(cur_bezier, cur_progress, y_len)
                    res[k] = self._mix(value_range[1][k], value_range[2][k], p, y_len)
                end
                return res

            else
                local p = self:_cubicBezier01(bezier, cur_progress, y_len)
                if  info[4] ~= nil
                and info[5] ~= nil
                and (info[4][1] == ThreeD_SPATIAL or info[4][1] == TwoD_SPATIAL)
                and info[5][1] == 0
                then
                    local coord = self:_cubicBezierSpatial(
                        info['lenInfo'],
                        value_range[1], 
                        value_range[3], 
                        value_range[4], 
                        value_range[2], 
                        p
                    )
                    if info[4][1] == TwoD_SPATIAL then
                        return {coord[1], coord[2]}
                    end
                    return coord
                end

                if type(value_range[1]) == "table" then
                    local res = {}
                    for j = 1, #value_range[1] do
                        res[j] = self._mix(value_range[1][j], value_range[2][j], p, y_len)
                    end
                    return res
                end
                return self._mix(value_range[1], value_range[2], p, y_len)
            end
        end
    end

    local first_info = content[1]
    local start_frame = first_info[2][1]
    if cur_frame<start_frame then
        return deepcopy(first_info[3][1])
    end

    local last_info = content[#content]
    local end_frame = last_info[2][2]
    if cur_frame>=end_frame then
        return deepcopy(last_info[3][2])
    end
    return nil
end

HallucinationEffect = {}

function HallucinationEffect:matchWithId(effectId)
    return 'KFM KSkr HallucinationEffect' == effectId
end

function HallucinationEffect.createWithId(effectId)
    if not HallucinationEffect:matchWithId(effectId) then
        return nil
    end
    local o = {
        program1 = {},
        program2 = {},
        program3 = {},
        program4 = {},
        program5 = {},
        program6 = {},
        program7 = {},
        program8 = {},
        currentWidth = 0,
        currentHeight = 0
    }
    o = newObject(o, HallucinationEffect)
    o:init()
    return o;
end

function HallucinationEffect:init()
    self.program1 = CGE.ProgramObject()
    self.program1:bindAttribLocation('position', 0)
    self.program1:initWithShaderStrings(vs, layer_fs)
    self.program1:bind()
    self.program1:sendUniformi('u_baseTexure', 0)
    self.program1:sendUniformi('u_sourceTexture', 1)
    self.mvMatLoc = self.program1:uniformLocation('u_mvMat')
    self.pMatLoc = self.program1:uniformLocation('u_pMat')

    self.program2 = CGE.ProgramObject()
    self.program2:bindAttribLocation('position', 0)
    self.program2:initWithShaderStrings(vs, grayscale_fs)
    self.program2:bind()
    self.program2:sendUniformi('inputImageTexture', 0)

    self.program3 = CGE.ProgramObject()
    self.program3:bindAttribLocation('position', 0)
    self.program3:initWithShaderStrings(vs, blur_fs)
    self.program3:bind()
    self.program3:sendUniformi('inputImageTexture', 0)

    self.program4 = CGE.ProgramObject()
    self.program4:bindAttribLocation('position', 0)
    self.program4:initWithShaderStrings(vs, distort_fs)
    self.program4:bind()
    self.program4:sendUniformi('inputImageTexture', 0)
    self.program4:sendUniformi('u_map', 1)

    self.program5 = CGE.ProgramObject()
    self.program5:bindAttribLocation('position', 0)
    self.program5:initWithShaderStrings(vs, gauss_fs)
    self.program5:bind()
    self.program5:sendUniformi('inputImageTexture', 0)

    self.program6 = CGE.ProgramObject()
    self.program6:bindAttribLocation('position', 0)
    self.program6:initWithShaderStrings(vs, bokeh_fs)
    self.program6:bind()
    self.program6:sendUniformi('inputImageTexture', 0)

    self.program7 = CGE.ProgramObject()
    self.program7:bindAttribLocation('position', 0)
    self.program7:initWithShaderStrings(vs, shadow_highlight_fs)
    self.program7:bind()
    self.program7:sendUniformi('inputImageTexture', 0)

    self.program8 = CGE.ProgramObject()
    self.program8:bindAttribLocation('position', 0)
    self.program8:initWithShaderStrings(vs, temperature_tone_fs)
    self.program8:bind()
    self.program8:sendUniformi('inputImageTexture', 0)

    local buffer = {}
    glGenBuffers(1,buffer) 
    self.vertexBuffer = buffer[1]
    local vertices = {-1,-1,1,-1,-1,1,1,1}
    local verticesData = CGE.FloatBuffer:alloc(#vertices)
    verticesData:put(#vertices, vertices, 0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glBufferData(GL_ARRAY_BUFFER, #vertices, verticesData:position(0), GL_STATIC_DRAW)

    self.keyframes = AETools.new(ae_keyframes)
end

function HallucinationEffect:updateValue(index, val1, val2, val3)
    if index == 1 then
        -- Progress
        self.progress = val1 / 100.0 
    end
end

function HallucinationEffect:resize(width, height)

end

function HallucinationEffect:customResize(width, height)
    self.currentWidth = width
    self.currentHeight = height
end

function HallucinationEffect:mul16(a, b)
    local c = {}
    for i = 0, 3 do
        for j = 0, 3 do
            local s = 0
            for k = 0, 3 do s = s + a[i*4 + k + 1] * b[k*4 + j + 1] end
            c[i*4 + j + 1] = s
        end
    end
    return c
end

function HallucinationEffect:invProj(aspect)
    local n, f = 0.1, 100
    local t = 0.3600238          -- tan(fovy/2)
    local a = aspect / t         -- x 方向系数
    local b = 1 / t              -- y 方向系数

    -- 把 1/a 与 1/b 互换，得到想要的顺序
    return {
        1/b, 0,   0,   0,        -- [0][0]
        0,   1/a, 0,   0,        -- [1][1]
        0,   0,   0,  -1/(2*f*n/(f-n)),  -- [2][3]
        0,   0,  -1,  -(f+n)/(2*f*n)     -- [3][2] & [3][3]
    }
end

function HallucinationEffect:updateTRS(ratio, offX, offY)
    -- 1. 模型矩阵（单位）
    local mMat = {
        1,0,0,0,
        0,1,0,0,
        0,0,1,0,
        offX,offY,0,1
    }
    -- 2. 视图矩阵（仅 -Z 平移）
    local posZ = 2.7776069 * ratio
    local vMat = {
        ratio,0,0,0,
        0,1,0,0,
        0,0,1,0,
        0,0,-posZ,1
    }
    -- 3. 视图-模型乘积
    local vmMat = self:mul16(vMat, mMat)
    -- 4. 投影逆矩阵
    local invPMat = self:invProj(ratio)
    -- 5. 返回两个 16 元表
    return {vmMat, invPMat}
end

function HallucinationEffect:cvtTable2Amaz(attrType, v)
    local value = nil
    if attrType == "number" then
        if #v == 1 then
            value = v[1]
        end
    elseif attrType == "vector" then
        if #v == 2 then
            value = {v[1], v[2]}
        elseif #v == 3 then
            value = {v[1], v[2], v[3]}
        elseif #v == 4 then
            value = {v[1], v[2], v[3], v[4]}
        end
    elseif attrType == "color" then
        if #v == 3 then
            value = {v[1], v[2], v[3], 1.0}
        elseif #v == 4 then
            value = {v[1], v[2], v[3], v[4]}
        end
    end
    return value
end

function HallucinationEffect:getHighlightParam(intensity)
    local p = intensity
    local p2 = p * p
    local p3 = p2 * p
    local p4 = p3 * p
    local param = 1.0 + 0.503 * p + 0.183 * p2 + 0.147 * p3 + 0.067 * p4
    return param
end

function HallucinationEffect:clamp(value, min, max)
    return math.min(math.max(value, min), max)
end

local extraData = {
    0, 0.18006, 0.26352, -0.24341,
    10, 0.18066, 0.26589, -0.25479,
    20, 0.18133, 0.26846, -0.26876,
    30, 0.18208, 0.27119, -0.28539,
    40, 0.18293, 0.27407, -0.30470,
    50, 0.18388, 0.27709, -0.32675,
    60, 0.18494, 0.28021, -0.35156,
    70, 0.18611, 0.28342, -0.37915,
    80, 0.18740, 0.28668, -0.40955,
    90, 0.18880, 0.28997, -0.44278,
    100, 0.19032, 0.29326, -0.47888,
    125, 0.19462, 0.30141, -0.58204,
    150, 0.19962, 0.30921, -0.70471,
    175, 0.20525, 0.31647, -0.84901,
    200, 0.21142, 0.32312, -1.0182,
    225, 0.21807, 0.32909, -1.2168,
    250, 0.22511, 0.33439, -1.4512,
    275, 0.23247, 0.33904, -1.7298,
    300, 0.24010, 0.34308, -2.0637,
    325, 0.24792, 0.34655, -2.4681,
    350, 0.25591, 0.34951, -2.9641,
    375, 0.26400, 0.35200, -3.5814,
    400, 0.27218, 0.35407, -4.3633,
    425, 0.28039, 0.35577, -5.3762,
    450, 0.28863, 0.35714, -6.7262,
    475, 0.29685, 0.35823, -8.5955,
    500, 0.30505, 0.35907, -11.324,
    525, 0.31320, 0.35968, -15.628,
    550, 0.32129, 0.36011, -23.325,
    575, 0.32931, 0.36038, -40.770,
    600, 0.33724, 0.36051, -116.45,
}

local A = {{0.8951, 0.2664, -0.1614}, {-0.7502, 1.7135, 0.0367}, {0.0389, -0.0685, 1.0296}}
local B = {{0.987, -0.1471, 0.16}, {0.4323, 0.5184, 0.0493}, {-0.0085, 0.04, 0.9685}}
local P = {
    {0.4123907992659595, 0.357584339383878, 0.1804807884018343},
    {0.21263900587151036, 0.715168678767756, 0.07219231536073371},
    {0.019330818715591832, 0.11919477979462598, 0.9505321522496607}
}
local Q = {
    {3.2409699419045213, -1.5373831775700935, -0.4986107602930033},
    {-0.9692436362808796, 1.8759675015077208, 0.04155505740717562},
    {0.05563007969699364, -0.20397695888897655, 1.0569715142428784}
}

function HallucinationEffect:computeVec3(x, y)
    local function mix(x, y, a)
        return x * (1. - a) + y * a
    end
    x = 1000000.0 / x
    y = y * 0.0001
    local index = 5
    local data = extraData[index]
    index = index + 4
    while (data <= x and index < #extraData + 1) do
        data = extraData[index]
        index = index + 4
    end
    local factor = (data - x) / (data - extraData[index - 2 * 4])
    local temp_1 = {
        mix(extraData[index - 3], extraData[index - 7], factor),
        mix(extraData[index - 2], extraData[index - 6], factor),
    }
    local a = extraData[index - 5]
    local b = extraData[index - 1]
    local sqA = math.sqrt(a * a + 1.0)
    local sqB = math.sqrt(b * b + 1.0)
    local temp_2 = {
        mix(1. / sqB, 1. / sqA, factor),
        mix(b / sqB, a / sqA, factor)
    }
    factor = math.sqrt(temp_2[1] * temp_2[1] + temp_2[2] * temp_2[2])
    temp_1 = {
        y * temp_2[1] / factor + temp_1[1],
        y * temp_2[2] / factor + temp_1[2],
    }
    temp_2 = -4.0 * temp_1[2] + temp_1[1] + 2.0
    a = temp_1[1] * 1.5 / temp_2
    b = temp_1[2] / temp_2
    a = self:clamp(a, 0.000001, 0.999999)
    b = self:clamp(b, 0.000001, 0.999999)
    if (a + b > 0.999999) then
        local t = 0.999999 / (a + b)
        a = a / t
        b = b / t
    end
    return {a / b, 1.0, (1. - a - b) / b}
end

function HallucinationEffect:Mat3xVec3(mat3, vec3)
    return {
        mat3[1][1] * vec3[1] + mat3[1][2] * vec3[2] + mat3[1][3] * vec3[3],
        mat3[2][1] * vec3[1] + mat3[2][2] * vec3[2] + mat3[2][3] * vec3[3],
        mat3[3][1] * vec3[1] + mat3[3][2] * vec3[2] + mat3[3][3] * vec3[3]
    }
end

function HallucinationEffect:diag(vec3)
    return {
        {vec3[1], 0.0, 0.0},
        {0.0, vec3[2], 0.0},
        {0.0, 0.0, vec3[3]}
    }
end

function HallucinationEffect:Vec3xMat3(vec3, mat3)
    return {
        mat3[1][1] * vec3[1] + mat3[2][1] * vec3[2] + mat3[3][1] * vec3[3],
        mat3[1][2] * vec3[1] + mat3[2][2] * vec3[2] + mat3[3][2] * vec3[3],
        mat3[1][3] * vec3[1] + mat3[2][3] * vec3[2] + mat3[3][3] * vec3[3]
    }
end

function HallucinationEffect:Mat3xMat3(mat3_1, mat3_2)
    return {self:Vec3xMat3(mat3_1[1], mat3_2),
            self:Vec3xMat3(mat3_1[2], mat3_2),
            self:Vec3xMat3(mat3_1[3], mat3_2)}
end

function HallucinationEffect:render(outFBO, inputTex)
    local viewportSize = {}
    glGetIntegerv(GL_VIEWPORT, 4, viewportSize)
    self:customResize(viewportSize[3], viewportSize[4])

    local aeDuration = 1.5
    local curTime = self.progress * 1.5
    curTime = math.min(curTime, aeDuration)

    local v = self.keyframes:GetVal("LumiLayer_103-trs#position#vector", curTime)
    local val = self:cvtTable2Amaz("vector", v)

    local ratio = self.currentWidth / self.currentHeight
    local offsetX = (val[1] / 1280 - 0.5) * 2 * ratio
    local offsetY = (val[2] / 1280 - 0.5) * 2
    local mvp = self:updateTRS(ratio, offsetX, offsetY)

    --- 198
    local fbo1 = AESP:takeCachedFrameBuffer(self.currentWidth, self.currentHeight)
    fbo1:bind()
    self.program1:bind()
    self.program1:sendUniformi('u_blendMode', 0)
    self.program1:sendUniformi('u_layerType', 1)
    self.program1:sendUniformf('u_layerOpacity', 1.0)
    self.program1:sendUniformi('u_hasBlend', 0)
    self.program1:sendUniformi('u_hasBaseTexture', 1)
    self.program1:sendUniformi('u_hasSourceTexture', 1)
    self.program1:sendUniformi('u_hasTrs', 1)
    self.program1:sendUniformf('u_mirrorEdge', 1.0)
    self.program1:sendUniformf('u_alpha', 1.0)
    glUniformMatrix4fv(self.mvMatLoc, 1, 0, mvp[1])
    glUniformMatrix4fv(self.pMatLoc, 1, 0, mvp[2])
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, inputTex)
    glActiveTexture(GL_TEXTURE1)
    glBindTexture(GL_TEXTURE_2D, inputTex)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    v = self.keyframes:GetVal("LumiLayer_102-trs-blend#position#vector", curTime)
    val = self:cvtTable2Amaz("vector", v)

    offsetX = (val[1] / 1280 - 0.5) * 2 * ratio
    offsetY = (1 - val[2] / 1280 - 0.5) * 2
    mvp = self:updateTRS(ratio, offsetX, offsetY)

    local alpha = self.keyframes:GetVal("LumiLayer_102-trs-blend#opacity#number", curTime)[1] / 100.0 
    --- 199
    local fbo2 = AESP:takeCachedFrameBuffer(self.currentWidth, self.currentHeight)
    fbo2:bind()
    self.program1:bind()
    self.program1:sendUniformi('u_blendMode', 0)
    self.program1:sendUniformi('u_layerType', 0)
    self.program1:sendUniformf('u_layerOpacity', 1.0)
    self.program1:sendUniformi('u_hasBlend', 1)
    self.program1:sendUniformi('u_hasBaseTexture', 1)
    self.program1:sendUniformi('u_hasSourceTexture', 1)
    self.program1:sendUniformi('u_hasTrs', 1)
    self.program1:sendUniformf('u_mirrorEdge', 1.0)
    self.program1:sendUniformf('u_alpha', alpha)
    glUniformMatrix4fv(self.mvMatLoc, 1, 0, mvp[1])
    glUniformMatrix4fv(self.pMatLoc, 1, 0, mvp[2])
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo1:texId())
    glActiveTexture(GL_TEXTURE1)
    glBindTexture(GL_TEXTURE_2D, inputTex)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- 200
    local fbo3 = AESP:takeCachedFrameBuffer(self.currentWidth, self.currentHeight)
    fbo3:bind()
    self.program2:bind()
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo2:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)
    
    local blurMap = self.keyframes:GetVal("LumiDistortChroma_101-effect0#blurMap#number", curTime)[1]
    --- 201
    local fbo4 = AESP:takeCachedFrameBuffer(self.currentWidth * 0.25, self.currentHeight * 0.25)
    fbo4:bind()
    self.program3:bind()
    self.program3:sendUniformf('u_stride', 0.575)
    self.program3:sendUniformf('u_angle', 0.0)
    self.program3:sendUniformf('u_ScreenParams', self.currentWidth * 0.25, self.currentHeight * 0.25)
    self.program3:sendUniformi('u_steps', math.floor(blurMap))
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo3:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- 202
    local fbo5 = AESP:takeCachedFrameBuffer(self.currentWidth * 0.25, self.currentHeight * 0.25)
    fbo5:bind()
    self.program3:bind()
    self.program3:sendUniformf('u_stride', 0.575)
    self.program3:sendUniformf('u_angle', 90.0)
    self.program3:sendUniformf('u_ScreenParams', self.currentWidth * 0.25, self.currentHeight * 0.25)
    self.program3:sendUniformi('u_steps', math.floor(blurMap))
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo4:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- 203
    fbo4:bind()
    self.program3:bind()
    self.program3:sendUniformf('u_stride', 0.575)
    self.program3:sendUniformf('u_angle', 0.0)
    self.program3:sendUniformf('u_ScreenParams', self.currentWidth * 0.25, self.currentHeight * 0.25)
    self.program3:sendUniformi('u_steps', math.floor(blurMap))
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo5:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- 204
    fbo5:bind()
    self.program3:bind()
    self.program3:sendUniformf('u_stride', 0.575)
    self.program3:sendUniformf('u_angle', 90.0)
    self.program3:sendUniformf('u_ScreenParams', self.currentWidth * 0.25, self.currentHeight * 0.25)
    self.program3:sendUniformi('u_steps', math.floor(blurMap))
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo4:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    local distortScale = self.keyframes:GetVal("LumiDistortChroma_101-effect0#distortScale#number", curTime)[1]
    local direction = self.keyframes:GetVal("LumiDistortChroma_101-effect0#direction#number", curTime)[1]
    local warpRed = self.keyframes:GetVal("LumiDistortChroma_101-effect0#warpRed#number", curTime)[1]
    local amountRelX = self.keyframes:GetVal("LumiDistortChroma_101-effect0#amountRelX#number", curTime)[1]
    --- 205
    fbo1:bind()
    self.program4:bind()
    self.program4:sendUniformi('u_wrapModeX', 0)
    self.program4:sendUniformi('u_wrapModeY', 0)
    self.program4:sendUniformf('u_ScreenParams', self.currentWidth, self.currentHeight)
    self.program4:sendUniformf('u_distortScale', distortScale * 15)
    self.program4:sendUniformf('u_direction', -direction)
    self.program4:sendUniformi('u_steps', 19)
    self.program4:sendUniformf('u_warpRed', warpRed)
    self.program4:sendUniformf('u_warpBlue', 1.0)
    self.program4:sendUniformf('u_amountRelX', amountRelX)
    self.program4:sendUniformf('u_amountRelY', 1.0)
    self.program4:sendUniformf('u_color1', 1., 0., 0.)
    self.program4:sendUniformf('u_color2', 0., 1., 0.)
    self.program4:sendUniformf('u_color3', 0., 0., 1.)
    self.program4:sendUniformf('u_mix', 1.0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo2:texId())
    glActiveTexture(GL_TEXTURE1)
    glBindTexture(GL_TEXTURE_2D, fbo5:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    local sample = self.keyframes:GetVal("LumiBokehBlur_101-effect1#sample#number", curTime)[1]
    local intensity = sample / 79
    local blur_intensity = math.pow(intensity, 0.35)
    --- 206
    fbo3:bind()
    self.program5:bind()
    self.program5:sendUniformf('u_sample', 22 * blur_intensity * 0.7)
    self.program5:sendUniformf('u_baseTexWidth', self.currentWidth)
    self.program5:sendUniformf('u_baseTexHeight', self.currentHeight)
    self.program5:sendUniformf('blurDir', 0.0, 1.0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo1:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- 207
    fbo1:bind()
    self.program5:bind()
    self.program5:sendUniformf('u_sample', 22 * blur_intensity * 0.7)
    self.program5:sendUniformf('u_baseTexWidth', self.currentWidth)
    self.program5:sendUniformf('u_baseTexHeight', self.currentHeight)
    self.program5:sendUniformf('blurDir', 1.0, 0.0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo3:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- 208
    fbo3:bind()
    self.program6:bind()
    self.program6:sendUniformf('u_blurSize', 7.5 * intensity * 0.7)
    self.program6:sendUniformf('u_baseTexWidth', self.currentWidth)
    self.program6:sendUniformf('u_baseTexHeight', self.currentHeight)
    self.program6:sendUniformf('u_lightIns', 1.0)
    self.program6:sendUniformf('u_intensity', blur_intensity)
    self.program6:sendUniformf('u_regionIns', 0.5)
    self.program6:sendUniformf('u_quality', 1.0)
    self.program6:sendUniformf('u_scaleX', 1.0)
    self.program6:sendUniformf('u_scaleY', 1.0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo1:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    local highlightIntensity = self.keyframes:GetVal("LumiShadowHighlight_101-effect2#highlightIntensity#number", curTime)[1]
    local highlightParam = self:getHighlightParam(highlightIntensity)
    --- 210
    fbo1:bind()
    self.program7:bind()
    self.program7:sendUniformf('u_highlightParam', highlightParam)
    self.program7:sendUniformf('u_shadowParam', 1.0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo3:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- 211
    local temperatureIntensity = self.keyframes:GetVal("LumiTemperatureTone_101-effect3#temperatureIntensity#number", curTime)[1]
    temperatureIntensity = self:clamp(temperatureIntensity, -1, 1)
    local toneIntensity = self:clamp(0, -1, 1)
    local t = temperatureIntensity
    local t2 = t * t
    local t3 = t2 * t
    local temperature = 6500. - 1970. * t + 876. * t2 - 2630. * t3
    local tone = toneIntensity * 100.

    fbo3:bind()
    self.program8:bind()
    if temperature == 6500. and tone == 0. then
        self.program8:sendUniformf('u_redVec3', 1., 0, 0)
        self.program8:sendUniformf('u_greenVec3', 0, 1., 0)
        self.program8:sendUniformf('u_blueVec3', 0, 0, 1.)
    else
        local vec3 = self:computeVec3(temperature, tone)
        local vec3Base = self:computeVec3(6500, 0)

        vec3 = self:Mat3xVec3(A, vec3)
        vec3Base = self:Mat3xVec3(A, vec3Base)
        local D = self:diag({vec3[1] / vec3Base[1], vec3[2] / vec3Base[2], vec3[3] / vec3Base[3]})
        local tmp = self:Mat3xMat3(D, A)
        tmp = self:Mat3xMat3(B, tmp)
        tmp = self:Mat3xMat3(tmp, P)
        tmp = self:Mat3xMat3(Q, tmp)
        self.program8:sendUniformf('u_redVec3', tmp[1][1], tmp[1][2], tmp[1][3])
        self.program8:sendUniformf('u_greenVec3', tmp[2][1], tmp[2][2], tmp[2][3])
        self.program8:sendUniformf('u_blueVec3', tmp[3][1], tmp[3][2], tmp[3][3])
    end
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo1:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    glViewport(0, 0, self.currentWidth, self.currentHeight)
    self.program1:bind()
    self.program1:sendUniformi('u_blendMode', 0)
    self.program1:sendUniformi('u_layerType', 1)
    self.program1:sendUniformf('u_layerOpacity', 1.0)
    self.program1:sendUniformi('u_hasBlend', 1)
    self.program1:sendUniformi('u_hasBaseTexture', 1)
    self.program1:sendUniformi('u_hasSourceTexture', 1)
    self.program1:sendUniformi('u_hasTrs', 0)
    self.program1:sendUniformf('u_mirrorEdge', 1.0)
    self.program1:sendUniformf('u_alpha', alpha)
    glUniformMatrix4fv(self.mvMatLoc, 1, 0, mvp[1])
    glUniformMatrix4fv(self.pMatLoc, 1, 0, mvp[2])
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo2:texId())
    glActiveTexture(GL_TEXTURE1)
    glBindTexture(GL_TEXTURE_2D, fbo3:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    AESP:recycleCachedFrameBuffer(fbo1)
    AESP:recycleCachedFrameBuffer(fbo2)
    AESP:recycleCachedFrameBuffer(fbo3)
    AESP:recycleCachedFrameBuffer(fbo4)
    AESP:recycleCachedFrameBuffer(fbo5)
end

function HallucinationEffect:onDestroy()
    glDeleteBuffers(1, {self.vertexBuffer})
end
    