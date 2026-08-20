
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
local gaussX_fs = [[
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
]]

---@language GLSL
local gaussY_fs = [[
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
uniform float u_sampleY;
uniform float u_sigmaY;
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
        vec4 _108 = _t3;
        vec3 _114 = pow(_108.xyz, vec3(u_gamma));
        _t3.x = _114.x;
        _t3.y = _114.y;
        _t3.z = _114.z;
    }
    return _t3;
}

float _f1(float _p0, float _p1)
{
    return exp((((-0.5) * _p0) * _p0) / (_p1 * _p1));
}

float _f0(vec2 _p0)
{
    vec3 _49 = fract(vec3(((_p0 * u_ScreenParams.xy) + vec2(0.33329999446868896484375)).xyx) * 0.103100001811981201171875);
    vec3 _t1 = _49 + vec3(dot(_49, _49.yzx + vec3(33.3300018310546875)));
    return (fract(fract((_t1.x + _t1.y) * _t1.z)) * 2.0) - 1.0;
}

void main()
{
    if (u_sampleY < 9.9999997473787516355514526367188e-06)
    {
        gl_FragColor = texture2D(inputImageTexture, textureCoord);
        return;
    }
    vec2 param = textureCoord;
    vec4 _142 = _f2(inputImageTexture, param);
    vec4 _t4 = _142;
    float param_1 = 0.0;
    float param_2 = u_sigmaY;
    float _149 = _f1(param_1, param_2);
    float _t5 = _149;
    vec4 _t6 = _142 * _149;
    vec2 _t7 = textureCoord;
    if (u_spaceDither > 9.9999997473787516355514526367188e-06)
    {
        vec2 param_3 = textureCoord;
        _t7 += (vec2(u_stepX, u_stepY) * (u_spaceDither * _f0(param_3)));
    }
    vec2 _t9 = _t7;
    for (mediump int _t10 = 1; _t10 <= 1024; _t10++)
    {
        mediump float _190 = float(_t10);
        if (_190 > u_sampleY)
        {
            break;
        }
        float _200 = _190 * u_stepY;
        float param_4 = _200;
        float param_5 = u_sigmaY;
        float _206 = _f1(param_4, param_5);
        _t9.y = _t7.y - _200;
        if (_t9.y < 0.0)
        {
            if (u_borderType == 1)
            {
                _t9.y = 0.0;
                vec2 param_6 = _t9;
                _t6 += (_f2(inputImageTexture, param_6) * _206);
                _t5 += _206;
            }
            else
            {
                if (u_borderType == 2)
                {
                    _t5 += _206;
                }
                else
                {
                    if (u_borderType == 3)
                    {
                        _t9.y = -_t9.y;
                        vec2 param_7 = _t9;
                        _t6 += (_f2(inputImageTexture, param_7) * _206);
                        _t5 += _206;
                    }
                }
            }
        }
        else
        {
            vec2 param_8 = _t9;
            _t6 += (_f2(inputImageTexture, param_8) * _206);
            _t5 += _206;
        }
        _t9.y = _t7.y + _200;
        if (_t9.y > 1.0)
        {
            if (u_borderType == 1)
            {
                _t9.y = 1.0;
                vec2 param_9 = _t9;
                _t6 += (_f2(inputImageTexture, param_9) * _206);
                _t5 += _206;
            }
            else
            {
                if (u_borderType == 2)
                {
                    _t5 += _206;
                }
                else
                {
                    if (u_borderType == 3)
                    {
                        _t9.y = 2.0 - _t9.y;
                        vec2 param_10 = _t9;
                        _t6 += (_f2(inputImageTexture, param_10) * _206);
                        _t5 += _206;
                    }
                }
            }
        }
        else
        {
            vec2 param_11 = _t9;
            _t6 += (_f2(inputImageTexture, param_11) * _206);
            _t5 += _206;
        }
    }
    _t6 /= vec4(_t5);
    if (u_inverseGammaCorrection == 1)
    {
        vec4 _346 = _t6;
        vec3 _351 = pow(_346.xyz, vec3(1.0 / u_gamma));
        _t6.x = _351.x;
        _t6.y = _351.y;
        _t6.z = _351.z;
    }
    if (u_blurAlpha == 0)
    {
        _t6.w = _t4.w;
    }
    gl_FragColor = _t6;
}
]]

---@language GLSL
local threshold_fs = [[
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
]]

---@language GLSL
local blurX_fs = [[
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
]]

---@language GLSL
local blurY_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;

uniform float u_sampleY;
uniform float u_sigmaY;
uniform float u_stepY;
uniform float u_exposure;

float _f0(float _p0, float _p1)
{
    return exp((((-0.5) * _p0) * _p0) / (_p1 * _p1));
}

void main()
{
    if (u_sampleY < 9.9999997473787516355514526367188e-06)
    {
        gl_FragColor = texture2D(inputImageTexture, textureCoord);
        return;
    }
    float param = 0.0;
    float param_1 = u_sigmaY;
    float _58 = _f0(param, param_1);
    float _t1 = _58;
    vec4 _t2 = texture2D(inputImageTexture, textureCoord) * _58;
    vec2 _t3 = textureCoord;
    for (mediump int _t4 = 1; _t4 <= 1024; _t4++)
    {
        mediump float _80 = float(_t4);
        if (_80 > u_sampleY)
        {
            break;
        }
        float _91 = _80 * u_stepY;
        float param_2 = _91;
        float param_3 = u_sigmaY;
        float _97 = _f0(param_2, param_3);
        _t3.y = textureCoord.y - _91;
        if (_t3.y >= 0.0)
        {
            _t2 += (texture2D(inputImageTexture, _t3) * _97);
            _t1 += _97;
        }
        _t3.y = textureCoord.y + _91;
        if (_t3.y <= 1.0)
        {
            _t2 += (texture2D(inputImageTexture, _t3) * _97);
            _t1 += _97;
        }
    }
    vec4 _145 = _t2;
    vec4 _147 = _145 / vec4(_t1);
    _t2 = _147;
    vec3 _153 = _147.xyz * u_exposure;
    _t2.x = _153.x;
    _t2.y = _153.y;
    _t2.z = _153.z;
    gl_FragColor = clamp(_t2, vec4(0.0), vec4(1.0));
}
]]

---@language GLSL
local blend_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform mediump sampler2D u_glowTexture;

uniform float u_exposure;
uniform mediump int u_displayGlow;

vec4 _f0(vec4 _p0, vec4 _p1)
{
    return (_p0 + _p1) - (_p0 * _p1);
}

void main()
{
    mediump vec4 _33 = texture2D(inputImageTexture, textureCoord);
    vec4 _t1 = vec4(0.0);
    if (u_exposure > 0.001)
    {
        _t1 = texture2D(u_glowTexture, textureCoord);
    }
    vec4 _53 = _t1;
    vec3 _55 = _53.xyz * vec3(1.0, 1.0, 1.0);
    _t1.x = _55.x;
    _t1.y = _55.y;
    _t1.z = _55.z;
    vec4 param = _t1;
    vec4 param_1 = _33;
    if (u_displayGlow == 1)
    {
        gl_FragColor = clamp(_t1, vec4(0.0), vec4(1.0));
    }
    else
    {
        gl_FragColor = clamp(_f0(param, param_1), vec4(0.0), vec4(1.0));
    }
}
]]

HazySoftLight = {}

function HazySoftLight:matchWithId(effectId)
    return 'KFM KSkr HazySoftLight' == effectId
end

function HazySoftLight.createWithId(effectId)
    if not HazySoftLight:matchWithId(effectId) then
        return nil
    end
    local o = {
        -- drawer = {}
        gaussXProgram = {},
        gaussYProgram = {},
        thresholdProgram = {},
        blurXProgram = {},
        blurYProgram = {},
        blendProgram = {},
        currentWidth = 0,
        currentHeight = 0,
        lightIntensity = 0,
        lightBlurIntensity = 0
    }
    o = newObject(o, HazySoftLight)
    o:init()
    return o;
end

function HazySoftLight:init()
    self.gaussXProgram = CGE.ProgramObject()
    self.gaussXProgram:bindAttribLocation('position', 0)
    self.gaussXProgram:initWithShaderStrings(vs, gaussX_fs)
    self.gaussXProgram:bind()
    self.gaussXProgram:sendUniformi('inputImageTexture', 0)

    self.gaussYProgram = CGE.ProgramObject()
    self.gaussYProgram:bindAttribLocation('position', 0)
    self.gaussYProgram:initWithShaderStrings(vs, gaussY_fs)
    self.gaussYProgram:bind()
    self.gaussYProgram:sendUniformi('inputImageTexture', 0)

    self.thresholdProgram = CGE.ProgramObject()
    self.thresholdProgram:bindAttribLocation('position', 0)
    self.thresholdProgram:initWithShaderStrings(vs, threshold_fs)
    self.thresholdProgram:bind()
    self.thresholdProgram:sendUniformi('inputImageTexture', 0)

    self.blurXProgram = CGE.ProgramObject()
    self.blurXProgram:bindAttribLocation('position', 0)
    self.blurXProgram:initWithShaderStrings(vs, blurX_fs)
    self.blurXProgram:bind()
    self.blurXProgram:sendUniformi('inputImageTexture', 0)

    self.blurYProgram = CGE.ProgramObject()
    self.blurYProgram:bindAttribLocation('position', 0)
    self.blurYProgram:initWithShaderStrings(vs, blurY_fs)
    self.blurYProgram:bind()
    self.blurYProgram:sendUniformi('inputImageTexture', 0)

    self.blendProgram = CGE.ProgramObject()
    self.blendProgram:bindAttribLocation('position', 0)
    self.blendProgram:initWithShaderStrings(vs, blend_fs)
    self.blendProgram:bind()
    self.blendProgram:sendUniformi('inputImageTexture', 0)
    self.blendProgram:sendUniformi('u_glowTexture', 1)

    local buffer = {}
    glGenBuffers(1,buffer)
    self.vertexBuffer = buffer[1]
    local vertices = {-1,-1,1,-1,-1,1,1,1}
    local verticesData = CGE.FloatBuffer:alloc(#vertices)
    verticesData:put(#vertices, vertices, 0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glBufferData(GL_ARRAY_BUFFER, #vertices, verticesData:position(0), GL_STATIC_DRAW)
    glBindBuffer(GL_ARRAY_BUFFER, 0)
end

function HazySoftLight:updateValue(index, val1, val2, val3)
    if index == 1 then
        -- LightIntensity
        self.lightIntensity = val1 / 100.0
    elseif index == 2 then
        -- LightBlurIntensity
        self.lightBlurIntensity = val1 / 100.0
    end

end

function HazySoftLight:resize(width, height)

end

function HazySoftLight:customResize(width, height)
    self.currentWidth = width
    self.currentHeight = height
end

function HazySoftLight:getSampleNum(intensity)
    local scale = 1.
    local bias = 0.
    local s = scale
    if intensity <= 30 then
        scale = 0.5
        bias = 2.
        s = 0.78
    elseif intensity <= 100 then
        scale = 0.5
        bias = 10
        s = 0.66
    elseif intensity <= 200 then
        scale = 0.25
        bias = 50.
        s = 0.7
    else
        scale = 0.125
        bias = 80.
        s = 0.8
    end

    local sampleNum = scale * intensity + bias
    sampleNum = sampleNum * s
    if sampleNum < 2. then
        sampleNum = math.floor(sampleNum + 0.5)
    end
    return sampleNum
end

function HazySoftLight:getQualityParam(quality)
    local qualityParam = quality * 2. - 1.
    if qualityParam < 0. then
        qualityParam = 10 ^ qualityParam
    else
        qualityParam = qualityParam * 2. + 1.
    end
    return qualityParam
end

function HazySoftLight:getXYScale(width, height)
    local size1 = math.min(width, height)
    local size2 = math.max(width, height) / 2.
    local baseSize = math.max(size1, size2)

    local xScale = baseSize / width
    local yScale = baseSize / height
    return xScale, yScale
end

function HazySoftLight:getSampleNumBlur(intensity)
    local scale = 1.
    local bias = 0.
    local s = scale
    if intensity <= 10 then
        scale = 0.8
        bias = 0.
        s = 1.0
    elseif intensity <= 50 then
        scale = 0.7
        bias = 2.
        s = 0.78
    elseif intensity <= 200 then
        scale = 0.5
        bias = 10
        s = 0.66
    else
        scale = 0.25
        bias = 60.
        s = 0.7
    end

    local sampleNum = scale * intensity + bias
    sampleNum = sampleNum * s
    if sampleNum < 2. then
        sampleNum = math.floor(sampleNum + 0.5)
    end
    return sampleNum, scale
end

function HazySoftLight:getBlurParam(intensity, xScale, yScale, sampleNum, qualityParam)
    local radiusX = xScale * intensity / 1000.0
    local radiusY = yScale * intensity / 1000.0
    local sigmaX = radiusX / 2.5
    local sigmaY = radiusY / 2.5
    local sampleX = sampleNum * qualityParam
    local sampleY = sampleNum * qualityParam
    local dx = radiusX / math.max(sampleX, 1e-5)
    local dy = radiusY / math.max(sampleY, 1e-5)
    return sampleX, sampleY, sigmaX, sigmaY, dx, dy
end

function HazySoftLight:render(outFBO, inputTex)
    local viewportSize = {}
    glGetIntegerv(GL_VIEWPORT, 4, viewportSize)
    self:customResize(viewportSize[3], viewportSize[4])

    local sampleX = self:getSampleNum(5.0) * self:getQualityParam(0.408759)
    local xScale, yScale = self:getXYScale(self.currentWidth, self.currentHeight)
    local radiusX = xScale * 5.0 / 1000.0
    local radiusY = yScale * 5.0 / 1000.0

    --- draw3
    local fbo1 = AESP:takeCachedFrameBuffer(self.currentWidth / 2.0, self.currentHeight / 2.0)
    fbo1:bind()
    self.gaussXProgram:bind()
    self.gaussXProgram:sendUniformf('u_ScreenParams', self.currentWidth / 2.0, self.currentHeight / 2.0)
    self.gaussXProgram:sendUniformi('u_inverseGammaCorrection', 1)
    self.gaussXProgram:sendUniformf('u_gamma', 2.2)
    self.gaussXProgram:sendUniformf('u_sampleX', sampleX)
    self.gaussXProgram:sendUniformf('u_sigmaX', radiusX / 2.5)
    self.gaussXProgram:sendUniformf('u_spaceDither', 0.0)
    self.gaussXProgram:sendUniformf('u_stepX', radiusX / math.max(sampleX, 1e-5))
    self.gaussXProgram:sendUniformf('u_stepY', radiusY / math.max(sampleX, 1e-5))
    self.gaussXProgram:sendUniformi('u_borderType', 0)
    self.gaussXProgram:sendUniformi('u_blurAlpha', 1)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, inputTex)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw4
    local fbo2 = AESP:takeCachedFrameBuffer(self.currentWidth / 2.0, self.currentHeight / 2.0)
    fbo2:bind()
    self.gaussYProgram:bind()
    self.gaussYProgram:sendUniformf('u_ScreenParams', self.currentWidth / 2.0, self.currentHeight / 2.0)
    self.gaussYProgram:sendUniformi('u_inverseGammaCorrection', 1)
    self.gaussYProgram:sendUniformf('u_gamma', 2.2)
    self.gaussYProgram:sendUniformf('u_sampleY', sampleX)
    self.gaussYProgram:sendUniformf('u_sigmaY', radiusY / 2.5)
    self.gaussYProgram:sendUniformf('u_spaceDither', 0.0)
    self.gaussYProgram:sendUniformf('u_stepX', radiusX / math.max(sampleX, 1e-5))
    self.gaussYProgram:sendUniformf('u_stepY', radiusY / math.max(sampleX, 1e-5))
    self.gaussYProgram:sendUniformi('u_borderType', 0)
    self.gaussYProgram:sendUniformi('u_blurAlpha', 1)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo1:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw5 
    local fbo3 = AESP:takeCachedFrameBuffer(self.currentWidth, self.currentHeight)
    fbo3:bind()
    self.thresholdProgram:bind()
    self.thresholdProgram:sendUniformi('u_thresholdType', 0)
    self.thresholdProgram:sendUniformf('u_thresholdLow', 0.268544)
    self.thresholdProgram:sendUniformf('u_thresholdHigh', 0.81)
    self.thresholdProgram:sendUniformf('u_thresholdSmooth', 0.482759)
    self.thresholdProgram:sendUniformf('u_grayScale', 0.59)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo2:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)


    local sampleNumBlur = self:getSampleNumBlur(25.0 + self.lightBlurIntensity * 75.0)
    local qualityParamBlur = self:getQualityParam(0.20438)
    local sampleXBlur, sampleYBlur, sigmaXBlur, sigmaYBlur, dxBlur, dyBlur = self:getBlurParam(25.0 + self.lightBlurIntensity * 75.0, xScale, yScale, sampleNumBlur, qualityParamBlur)

    --- draw6
    fbo1:bind()
    self.blurXProgram:bind()
    self.blurXProgram:sendUniformf('u_sampleX', sampleXBlur)
    self.blurXProgram:sendUniformf('u_sigmaX', sigmaXBlur)
    self.blurXProgram:sendUniformf('u_stepX', dxBlur)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo3:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw7
    fbo2:bind()
    self.blurYProgram:bind()
    self.blurYProgram:sendUniformf('u_sampleY', sampleYBlur)
    self.blurYProgram:sendUniformf('u_sigmaY', sigmaYBlur)
    self.blurYProgram:sendUniformf('u_stepY', dyBlur)
    self.blurYProgram:sendUniformf('u_exposure', 0.9 * math.max(1.0 * (self.lightIntensity - 0.01), 0.01))
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo1:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw8
    local fbo6 = AESP:takeCachedFrameBuffer(self.currentWidth, self.currentHeight)
    fbo6:bind()
    self.blendProgram:bind()
    self.blendProgram:sendUniformi('u_displayGlow', 0)
    self.blendProgram:sendUniformf('u_exposure', 0.9 * math.max(1.0 * (self.lightIntensity - 0.01), 0.01))
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo2:texId())
    glActiveTexture(GL_TEXTURE1)
    glBindTexture(GL_TEXTURE_2D, inputTex)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    sampleX = self:getSampleNum(5.0 * self.lightIntensity) * self:getQualityParam(0.408759)
    xScale, yScale = self:getXYScale(self.currentWidth, self.currentHeight)
    radiusX = xScale * 5.0 * self.lightIntensity / 1000.0
    radiusY = yScale * 5.0 * self.lightIntensity / 1000.0
    ---draw12
    fbo1:bind()
    self.gaussXProgram:bind()
    self.gaussXProgram:sendUniformf('u_ScreenParams', self.currentWidth / 2.0, self.currentHeight / 2.0)
    self.gaussXProgram:sendUniformi('u_inverseGammaCorrection', 1)
    self.gaussXProgram:sendUniformf('u_gamma', 2.2)
    self.gaussXProgram:sendUniformf('u_sampleX', sampleX)
    self.gaussXProgram:sendUniformf('u_sigmaX', radiusX / 2.5)
    self.gaussXProgram:sendUniformf('u_spaceDither', 0.0)
    self.gaussXProgram:sendUniformf('u_stepX', radiusX / math.max(sampleX, 1e-5))
    self.gaussXProgram:sendUniformf('u_stepY', radiusY / math.max(sampleX, 1e-5))
    self.gaussXProgram:sendUniformi('u_borderType', 0)
    self.gaussXProgram:sendUniformi('u_blurAlpha', 1)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, inputTex)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw13
    fbo2:bind()
    self.gaussYProgram:bind()
    self.gaussYProgram:sendUniformf('u_ScreenParams', self.currentWidth / 2.0, self.currentHeight / 2.0)
    self.gaussYProgram:sendUniformi('u_inverseGammaCorrection', 1)
    self.gaussYProgram:sendUniformf('u_gamma', 2.2)
    self.gaussYProgram:sendUniformf('u_sampleY', sampleX)
    self.gaussYProgram:sendUniformf('u_sigmaY', radiusY / 2.5)
    self.gaussYProgram:sendUniformf('u_spaceDither', 0.0)
    self.gaussYProgram:sendUniformf('u_stepX', radiusX / math.max(sampleX, 1e-5))
    self.gaussYProgram:sendUniformf('u_stepY', radiusY / math.max(sampleX, 1e-5))
    self.gaussYProgram:sendUniformi('u_borderType', 0)
    self.gaussYProgram:sendUniformi('u_blurAlpha', 1)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo1:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw14
    local fbo10 = AESP:takeCachedFrameBuffer(self.currentWidth, self.currentHeight)
    fbo10:bind()
    self.thresholdProgram:bind()
    self.thresholdProgram:sendUniformi('u_thresholdType', 0)
    self.thresholdProgram:sendUniformf('u_thresholdLow', 0.268544)
    self.thresholdProgram:sendUniformf('u_thresholdHigh', 0.81)
    self.thresholdProgram:sendUniformf('u_thresholdSmooth', 0.482759)
    self.thresholdProgram:sendUniformf('u_grayScale', 0.59)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo2:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    sampleNumBlur = self:getSampleNumBlur(25.0 + self.lightBlurIntensity * 75.0)
    qualityParamBlur = self:getQualityParam(0.20438)
    sampleXBlur, sampleYBlur, sigmaXBlur, sigmaYBlur, dxBlur, dyBlur = self:getBlurParam(25.0 + self.lightBlurIntensity * 75.0, xScale, yScale, sampleNumBlur, qualityParamBlur)
    --- draw15
    fbo1:bind()
    self.blurXProgram:bind()
    self.blurXProgram:sendUniformf('u_sampleX', sampleXBlur)
    self.blurXProgram:sendUniformf('u_sigmaX', sigmaXBlur)
    self.blurXProgram:sendUniformf('u_stepX', dxBlur)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo10:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw16
    fbo2:bind()
    self.blurYProgram:bind()
    self.blurYProgram:sendUniformf('u_sampleY', sampleYBlur)
    self.blurYProgram:sendUniformf('u_sigmaY', sigmaYBlur)
    self.blurYProgram:sendUniformf('u_stepY', dyBlur)
    self.blurYProgram:sendUniformf('u_exposure', 1.0 * self.lightIntensity)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo1:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    --- draw17
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    glViewport(0, 0, self.currentWidth, self.currentHeight)
    self.blendProgram:bind()
    self.blendProgram:sendUniformi('u_displayGlow', 0)
    self.blendProgram:sendUniformf('u_exposure', 1.0 * self.lightIntensity)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, fbo6:texId())
    glActiveTexture(GL_TEXTURE1)
    glBindTexture(GL_TEXTURE_2D, fbo2:texId())
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    AESP:recycleCachedFrameBuffer(fbo1)
    AESP:recycleCachedFrameBuffer(fbo2)
    AESP:recycleCachedFrameBuffer(fbo3)
    AESP:recycleCachedFrameBuffer(fbo6)
    AESP:recycleCachedFrameBuffer(fbo10)
end

function HazySoftLight:onDestroy()
    glDeleteBuffers(1, {self.vertexBuffer})
end
    