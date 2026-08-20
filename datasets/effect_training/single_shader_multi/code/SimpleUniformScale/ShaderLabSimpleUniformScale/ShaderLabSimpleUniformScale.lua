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
varying vec2 textureCoord;

void main()
{
    textureCoord = position * 0.5 + 0.5;
    gl_Position = vec4(position, 0.0, 1.0);
}
]]

local fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

varying vec2 textureCoord;
uniform sampler2D inputImageTexture;
uniform float uProgress;
uniform float uTime;

void main()
{
    vec2 uv = textureCoord;
    float bell = sin(clamp(uProgress, 0.0, 1.0) * 3.14159265);
    float scale = 1.0 + 0.55 * bell;
    vec2 sampleUV = (uv - vec2(0.5, 0.5)) / scale + vec2(0.5, 0.5);
    gl_FragColor = texture2D(inputImageTexture, sampleUV);
}
]]

ShaderLabSimpleUniformScale = {}

function ShaderLabSimpleUniformScale:matchWithId(effectId)
    return 'KFM ShaderLab ShaderLabSimpleUniformScale' == effectId
end

function ShaderLabSimpleUniformScale.createWithId(effectId)
    if not ShaderLabSimpleUniformScale:matchWithId(effectId) then
        return nil
    end
    local o = { drawer = {}, _frame = 0, _progress = 0.0 }
    o = newObject(o, ShaderLabSimpleUniformScale)
    o:init()
    return o
end

function ShaderLabSimpleUniformScale:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
end

function ShaderLabSimpleUniformScale:valueType(index)
    if index == 1 then
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function ShaderLabSimpleUniformScale:updateValue(index, val1, val2, val3)
    if index == 1 then
        self._progress = val1
    end
end

function ShaderLabSimpleUniformScale:resize(width, height)
end

function ShaderLabSimpleUniformScale:updateTimeAndFrame(time, frame)
    local f = frame or self._frame or 0
    self._frame = f
    self._progress = math.max(0.0, math.min(1.0, f / 124.0))
end

function ShaderLabSimpleUniformScale:_sendTimeUniforms()
    local p = self._progress or 0.0
    local program = self.drawer:getProgram()
    program:bind()
    program:sendUniformf("uProgress", p)
    program:sendUniformf("uTime", p * 5.0)
end

function ShaderLabSimpleUniformScale:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self:_sendTimeUniforms()
    self.drawer:drawTexture(inputTex)
    self._frame = ((self._frame or 0) + 1) % 125
    self._progress = math.max(0.0, math.min(1.0, (self._frame or 0) / 124.0))
end

function ShaderLabSimpleUniformScale:onDestroy()
end
