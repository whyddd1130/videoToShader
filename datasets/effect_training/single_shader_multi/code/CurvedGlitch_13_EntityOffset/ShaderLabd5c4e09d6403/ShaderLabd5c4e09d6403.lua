
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
#define u_offsetX (-0.08 + 0.16 * uProgress)
#define u_offsetY (0.08 - 0.16 * uProgress)
varying vec2 v_uv;

void main()
{
    vec4 _t0 = texture2D(inputImageTexture, v_uv);
    vec2 _34 = (vec2(u_offsetX, u_offsetY) * (vec2(1.0) - v_uv)) * v_uv;
    vec4 _t3 = texture2D(inputImageTexture, v_uv + _34);
    _t0.x = _t3.x;
    vec4 _t5 = texture2D(inputImageTexture, v_uv - _34);
    _t0.z = _t5.z;
    _t0.w = ((_t3.w + _t0.w) + _t5.w) / 3.0;
    gl_FragColor = _t0;
}


]]

ShaderLabd5c4e09d6403 = {}

function ShaderLabd5c4e09d6403:matchWithId(effectId)
    return 'KFM ShaderLab ShaderLabd5c4e09d6403' == effectId
end

function ShaderLabd5c4e09d6403.createWithId(effectId)
    if not ShaderLabd5c4e09d6403:matchWithId(effectId) then
        return nil
    end
    local o = { drawer = {}, _frame = 0, _progress = 0.0 }
    o = newObject(o, ShaderLabd5c4e09d6403)
    o:init()
    return o
end

function ShaderLabd5c4e09d6403:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
end

function ShaderLabd5c4e09d6403:valueType(index)
    if index == 1 then
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function ShaderLabd5c4e09d6403:updateValue(index, val1, val2, val3)
    if index == 1 then
        self._progress = val1
    end
end

function ShaderLabd5c4e09d6403:resize(width, height)
end

function ShaderLabd5c4e09d6403:updateTimeAndFrame(time, frame)
    local f = frame or self._frame or 0
    self._frame = f
    self._progress = math.max(0.0, math.min(1.0, f / 124.0))
end

function ShaderLabd5c4e09d6403:_sendTimeUniforms()
    local p = self._progress or 0.0
    local program = self.drawer:getProgram()
    program:bind()
    program:sendUniformf("uProgress", p)
    program:sendUniformf("uTime", p * 5.0)
end

function ShaderLabd5c4e09d6403:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self:_sendTimeUniforms()
    self.drawer:drawTexture(inputTex)
    self._frame = ((self._frame or 0) + 1) % 125
    self._progress = math.max(0.0, math.min(1.0, (self._frame or 0) / 124.0))
end

function ShaderLabd5c4e09d6403:onDestroy()
end
