
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

local preProcess_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

uniform sampler2D inputImageTexture;
uniform float threshold;
uniform float thresholdSmooth;
uniform float exposure;
uniform int blendMode;

varying vec2 textureCoord;

void main() 
{
    vec4 oriColor = texture2D(inputImageTexture, textureCoord);
    oriColor.rgb *= vec3(oriColor.a);
    // oriColor.a = 1.0;
    oriColor = max(oriColor, vec4(0.0));

    float thresholdPercent = 0.0;
    // if (isThreshold == 1)
    if (true) 
    {
        if (oriColor.r < threshold)
        {
            thresholdPercent = oriColor.r / threshold;
            oriColor.r = ((thresholdPercent * oriColor.r) * thresholdSmooth);
        }
        if (oriColor.g < threshold)
        {
            thresholdPercent = oriColor.g / threshold;
            oriColor.g = ((thresholdPercent * oriColor.g) * thresholdSmooth);
        }
        if (oriColor.b < threshold)
        {
            thresholdPercent = oriColor.b / threshold;
            oriColor.b = ((thresholdPercent * oriColor.b) * thresholdSmooth);
        }
    }

   // if (gammaCorrect == 1)
   // {
   //     oriColor.rgb = pow(oriColor.rgb, vec3(2.222222));
   // }
    if (blendMode == 1)
    {
        oriColor = min(oriColor, vec4(1.0));   // if screen, clamp all values at 1.0 and do exposure as post process
    }
    else
    {
        oriColor.rgb *= vec3(exposure);
    }

    gl_FragColor = oriColor;
}

]]

---@language GLSL
local blur_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

uniform sampler2D inputImageTexture;
uniform int steps;
uniform vec2 stride;

varying vec2 textureCoord;

float getWeight(float x)
{
    return exp(-0.5 * (x * x) / 0.06);
}

void main() 
{
    vec4 total = vec4(0.0);
    float totalWeight = 0.0;
    for (int i = -steps; i <= steps; i++)
    {
        vec2 texCoord = textureCoord + float(i) * stride;
        float weight = getWeight(float(i) / float(steps));
        total += weight * texture2D(inputImageTexture, texCoord);
        totalWeight += weight;
    }

    gl_FragColor = total / vec4(totalWeight);
}
]]

---@language GLSL
local postProcess_fs = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif // GL_FRAGMENT_PRECISION_HIGH

uniform sampler2D inputImageTexture;
uniform float exposure;
uniform int blendMode;

varying vec2 textureCoord;

void main() 
{
    vec4 resColor = texture2D(inputImageTexture, textureCoord);
    resColor.a = min(resColor.a, 1.0);

    if (blendMode == 1)
    {
        resColor.rgb *= vec3(exposure);
    }

   // if (gammaCorrect == 1)
   // {
   //     resColor.rgb = pow(resColor.rgb, vec3(0.45454545));
   // }

    resColor.a = min(resColor.a, 1.0);

    if (blendMode == 1)
    {
        resColor.rgb = min(resColor.rgb, 1.0);
    }

    gl_FragColor = resColor;
}    
]]

DeepGlow = {}

function DeepGlow:matchWithId(effectId)
    return 'KFM KSkr DeepGlow' == effectId
end

function DeepGlow.createWithId(effectId)
    if not DeepGlow:matchWithId(effectId) then
        return nil
    end
    local o = {
        preProcessDrawer = {},
        blurDrawer = {},
        postProcessDrawer = {},
        drawer = {},
        radius = 0.0,
        exposure = 1.0,
        threshold = 0.0,
        thresholdSmooth = 0.0,
        blendMode = 1,
        gammaCorrect = 1,
        width = 720,
        height = 1280,
        testValue = 1,
    }
    o = newObject(o, DeepGlow)
    o:init()
    return o;
end

function DeepGlow:init()
    self.preProcessDrawer = CGE.TextureDrawer:createWithShader(vs, preProcess_fs)
    self.blurDrawer = CGE.TextureDrawer:createWithShader(vs, blur_fs)
    self.postProcessDrawer = CGE.TextureDrawer:createWithShader(vs, postProcess_fs)
    self.drawer = CGE.TextureDrawer:create()
end

function DeepGlow:valueType(index)
    if index == 1 then
        -- radius
        return FM.AEValueType_OneDFloat
    elseif index == 2 then
        -- exposure
        return FM.AEValueType_OneDFloat
    elseif index == 3 then
        -- threshold
        return FM.AEValueType_OneDFloat
    elseif index == 4 then
        -- threshold smooth
        return FM.AEValueType_OneDFloat
    elseif index == 5 then
        -- blend mode
        return FM.AEValueType_OneDInt
    end
    return FM.AEValueType_No_Value
end

function DeepGlow:updateValue(index, val1, val2, val3)
    if index == 1 then
        -- radius
        self.radius = val1
    elseif index == 2 then
        -- exposure
        self.exposure = val1
    elseif index == 3 then
        -- threshold
        self.threshold = val1
    elseif index == 4 then
        -- threshold Smooth
        self.thresholdSmooth = val1
    elseif index == 5 then
        -- blend Mode
        self.blendMode = val1
    end
end

function DeepGlow:resize(width, height)
    if (width ~= self.width or height ~= self.height) then
        self.width = width
        self.height = height
    end
end

function DeepGlow:render(outFBO, inputTex)

    local viewportSize = {}
    glGetIntegerv(GL_VIEWPORT, 4, viewportSize)
    self:resize(viewportSize[3], viewportSize[4])


    local preProcessProgram = self.preProcessDrawer:getProgram()
    local blurProgram = self.blurDrawer:getProgram()
    local postProcessProgram = self.postProcessDrawer:getProgram()

    local highlightFbo = AESP:takeCachedFrameBuffer(self.width, self.height)
    highlightFbo:bind()
    preProcessProgram:bind()
    preProcessProgram:sendUniformf("threshold", self.threshold)
    preProcessProgram:sendUniformf("thresholdSmooth", self.thresholdSmooth)
    preProcessProgram:sendUniformf("exposure", self.exposure)
    preProcessProgram:sendUniformi("blendMode", self.blendMode)
    self.preProcessDrawer:drawTexture(inputTex)

    local blur1Fbo
    local blur2Fbo
    local blendFbo

    local steps = math.min(self.radius, 20)
    local iter = math.ceil(math.min(math.max(1, self.radius / steps), 6))
    local fixSteps = math.min(math.max(1, self.radius / iter), 20)

    blur1Fbo = AESP:takeCachedFrameBuffer(self.width, self.height)
    blur2Fbo = AESP:takeCachedFrameBuffer(self.width, self.height)

    blendFbo = AESP:takeCachedFrameBuffer(self.width, self.height)
    blendFbo:bind()
    self.drawer:drawTexture(highlightFbo:texId())
    if self.radius >= 0.01 then
        for i = 1, iter, 1 do
            blur1Fbo:bind()
            -- glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
            blurProgram:bind()
            blurProgram:sendUniformi("steps", fixSteps)
            blurProgram:sendUniformf("stride", 1.0 / self.width, 0.0)
            if i == 1 then
                self.blurDrawer:drawTexture(highlightFbo:texId())
            else
                self.blurDrawer:drawTexture(blur2Fbo:texId())
            end

            blur2Fbo:bind()
            blurProgram:bind()
            blurProgram:sendUniformi("steps", fixSteps)
            blurProgram:sendUniformf("stride", 0.0, 1.0 / self.height)
            self.blurDrawer:drawTexture(blur1Fbo:texId())


            
            blendFbo:bind()
            glEnable(GL_BLEND)
            if self.blendMode == 1 then
                glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_COLOR)
            else
                glBlendFunc(GL_ONE, GL_ONE)
            end
            self.drawer:drawTexture(blur2Fbo:texId())
            glDisable(GL_BLEND)
        end
    end

    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    postProcessProgram:bind()
    postProcessProgram:sendUniformf("exposure", self.exposure)
    postProcessProgram:sendUniformi("blendMode", self.blendMode)  
    self.postProcessDrawer:drawTexture(blendFbo:texId())  

    AESP:recycleCachedFrameBuffer(highlightFbo)
    AESP:recycleCachedFrameBuffer(blur1Fbo)
    AESP:recycleCachedFrameBuffer(blur2Fbo)
    AESP:recycleCachedFrameBuffer(blendFbo)

    -- test
    -- glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    -- self.drawer:drawTexture(blendFbo:texId())
end

function DeepGlow:onDestroy()
end
    