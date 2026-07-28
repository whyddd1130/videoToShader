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
    float p = clamp(uProgress, 0.0, 1.0);
    float bell = sin(p * 3.14159265);
    float flipAmount = smoothstep(0.0, 1.0, p);
    vec2 flipped = vec2(1.0 - uv.x, uv.y);
    vec2 baseUV = mix(uv, flipped, flipAmount);
    float radius = 0.30 * bell;
    vec4 color = vec4(0.0);
    color += texture2D(inputImageTexture, baseUV + vec2(-radius, 0.0)) * 0.08;
    color += texture2D(inputImageTexture, baseUV + vec2(-radius * 0.66, 0.0)) * 0.12;
    color += texture2D(inputImageTexture, baseUV + vec2(-radius * 0.33, 0.0)) * 0.16;
    color += texture2D(inputImageTexture, baseUV) * 0.28;
    color += texture2D(inputImageTexture, baseUV + vec2(radius * 0.33, 0.0)) * 0.16;
    color += texture2D(inputImageTexture, baseUV + vec2(radius * 0.66, 0.0)) * 0.12;
    color += texture2D(inputImageTexture, baseUV + vec2(radius, 0.0)) * 0.08;
    gl_FragColor = color;
}
]]

ShaderLabSimpleFlipSmearX = {}

function ShaderLabSimpleFlipSmearX:matchWithId(effectId)
    return 'KFM ShaderLab ShaderLabSimpleFlipSmearX' == effectId
end

function ShaderLabSimpleFlipSmearX.createWithId(effectId)
    if not ShaderLabSimpleFlipSmearX:matchWithId(effectId) then
        return nil
    end
    local o = { drawer = {}, _frame = 0, _progress = 0.0 }
    o = newObject(o, ShaderLabSimpleFlipSmearX)
    o:init()
    return o
end

function ShaderLabSimpleFlipSmearX:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
end

function ShaderLabSimpleFlipSmearX:valueType(index)
    if index == 1 then
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function ShaderLabSimpleFlipSmearX:updateValue(index, val1, val2, val3)
    if index == 1 then
        self._progress = val1
    end
end

function ShaderLabSimpleFlipSmearX:resize(width, height)
end

function ShaderLabSimpleFlipSmearX:updateTimeAndFrame(time, frame)
    local f = frame or self._frame or 0
    self._frame = f
    self._progress = math.max(0.0, math.min(1.0, f / 124.0))
end

function ShaderLabSimpleFlipSmearX:_sendTimeUniforms()
    local p = self._progress or 0.0
    local program = self.drawer:getProgram()
    program:bind()
    program:sendUniformf("uProgress", p)
    program:sendUniformf("uTime", p * 5.0)
end

function ShaderLabSimpleFlipSmearX:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self:_sendTimeUniforms()
    self.drawer:drawTexture(inputTex)
    self._frame = ((self._frame or 0) + 1) % 125
    self._progress = math.max(0.0, math.min(1.0, (self._frame or 0) / 124.0))
end

function ShaderLabSimpleFlipSmearX:onDestroy()
end
