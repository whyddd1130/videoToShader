
local function newObject(o, class)
    class.__index = class
    return setmetatable(o, class)
end

local vs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

attribute vec2 position;
varying vec2 uv;
varying vec2 uv0;
varying vec2 v_uv;
varying vec2 textureCoord;
varying vec2 texCoord;

void main()
{
    vec2 t = position * 0.5 + 0.5;
    uv = t;
    uv0 = t;
    v_uv = t;
    textureCoord = t;
    texCoord = t;
    gl_Position = vec4(position, 0.0, 1.0);
}

]]

local fs = [[
precision highp float;

uniform float uProgress;
uniform float uTime;
precision highp int;

uniform sampler2D inputImageTexture;
#define u_horz int(8.0 + 112.0 * uProgress)
#define u_vert int(8.0 + 112.0 * uProgress)
#define u_ScreenParams vec4(1080.0, 1080.0, 1.0/1080.0, 1.0/1080.0)
#define u_sharp 0
varying vec2 v_uv;

vec4 _f0(float _p0, vec2 _p1, vec2 _p2)
{
    return texture2D(inputImageTexture, _p1 + (_p2 * vec2(0.0, _p0))) + texture2D(inputImageTexture, _p1 - (_p2 * vec2(0.0, _p0)));
}

void main()
{
    bool _54 = u_horz == 0;
    bool _57 = u_vert == 0;
    if (_54 && _57)
    {
        gl_FragColor = texture2D(inputImageTexture, v_uv);
        return;
    }
    vec2 _t2 = vec2(float(u_horz), float(u_vert));
    if (_54)
    {
        _t2.x = (_t2.y * u_ScreenParams.x) / u_ScreenParams.y;
    }
    else
    {
        if (_57)
        {
            _t2.y = (_t2.x * u_ScreenParams.y) / u_ScreenParams.x;
        }
    }
    vec4 _t4;
    if (u_sharp == 1)
    {
        _t4 = texture2D(inputImageTexture, floor(_t2 * v_uv) / _t2);
    }
    else
    {
        vec2 _135 = (floor(_t2 * v_uv) + vec2(0.5)) / _t2;
        _t4 = texture2D(inputImageTexture, _135);
        vec2 _149 = ((vec2(1.0) / _t2) / vec2(4.0)) / vec2(2.0);
        float _t7 = 1.0;
        for (float _t8 = 1.0; _t8 <= 4.0; _t8 += 1.0)
        {
            float param = _t8;
            vec2 param_1 = _135;
            vec2 param_2 = _149;
            vec4 _168 = _t4;
            vec3 _170 = _168.xyz + _f0(param, param_1, param_2).xyz;
            _t4.x = _170.x;
            _t4.y = _170.y;
            _t4.z = _170.z;
            _t7 += 2.0;
        }
        vec4 _183 = _t4;
        vec3 _186 = _183.xyz / vec3(_t7);
        _t4.x = _186.x;
        _t4.y = _186.y;
        _t4.z = _186.z;
    }
    gl_FragColor = _t4;
}


]]

ShaderLab9e742e2d20d7 = {}

function ShaderLab9e742e2d20d7:matchWithId(effectId)
    return 'KFM ShaderLab ShaderLab9e742e2d20d7' == effectId
end

function ShaderLab9e742e2d20d7.createWithId(effectId)
    if not ShaderLab9e742e2d20d7:matchWithId(effectId) then
        return nil
    end
    local o = { drawer = {}, _frame = 0, _progress = 0.0 }
    o = newObject(o, ShaderLab9e742e2d20d7)
    o:init()
    return o
end

function ShaderLab9e742e2d20d7:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
end

function ShaderLab9e742e2d20d7:valueType(index)
    if index == 1 then
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function ShaderLab9e742e2d20d7:updateValue(index, val1, val2, val3)
    if index == 1 then
        self._progress = val1
    end
end

function ShaderLab9e742e2d20d7:resize(width, height)
end

function ShaderLab9e742e2d20d7:updateTimeAndFrame(time, frame)
    local f = frame or self._frame or 0
    self._frame = f
    self._progress = math.max(0.0, math.min(1.0, f / 124.0))
end

function ShaderLab9e742e2d20d7:_sendTimeUniforms()
    local p = self._progress or 0.0
    local program = self.drawer:getProgram()
    program:bind()
    program:sendUniformf("uProgress", p)
    program:sendUniformf("uTime", p * 5.0)
end

function ShaderLab9e742e2d20d7:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self:_sendTimeUniforms()
    self.drawer:drawTexture(inputTex)
    self._frame = ((self._frame or 0) + 1) % 125
    self._progress = math.max(0.0, math.min(1.0, (self._frame or 0) / 124.0))
end

function ShaderLab9e742e2d20d7:onDestroy()
end
