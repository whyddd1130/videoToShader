
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

uniform float amountToDecolor;
uniform vec3 colorOneToLeave;
uniform float toleranceOne;
uniform float edgeSoftnessOne;
uniform vec3 colorTwoToLeave;
uniform float toleranceTwo;
uniform vec3 colorThreeToLeave;
uniform float toleranceThree;
uniform vec3 colorFourToLeave;
uniform float toleranceFour;
uniform vec3 colorFiveToLeave;
uniform float toleranceFive;

void main() 
{
    vec4 color = texture2D(inputImageTexture, textureCoord);

    float maxValueOne = max(abs(color.r - colorOneToLeave.r), abs(color.g - colorOneToLeave.g));
    maxValueOne = max(maxValueOne, abs(color.b - colorOneToLeave.b));

    float maxValueTwo = max(abs(color.r - colorTwoToLeave.r), abs(color.g - colorTwoToLeave.g));
    maxValueTwo = max(maxValueTwo, abs(color.b - colorTwoToLeave.b));

    float maxValueThree = max(abs(color.r - colorThreeToLeave.r), abs(color.g - colorThreeToLeave.g));
    maxValueThree = max(maxValueThree, abs(color.b - colorThreeToLeave.b));

    float maxValueFour = max(abs(color.r - colorFourToLeave.r), abs(color.g - colorFourToLeave.g));
    maxValueFour = max(maxValueFour, abs(color.b - colorFourToLeave.b));

    float maxValueFive = max(abs(color.r - colorFiveToLeave.r), abs(color.g - colorFiveToLeave.g));
    maxValueFive = max(maxValueFive, abs(color.b - colorFiveToLeave.b));

    if(toleranceOne < maxValueOne && toleranceTwo < maxValueTwo && toleranceThree < maxValueThree && toleranceFour < maxValueFour && toleranceFive < maxValueFive)
    {
        float average = (color.r + color.g + color.b) / 3.0;
        vec3 grayColor = color.rgb + (vec3(average) - color.rgb) * amountToDecolor; 
        float m = smoothstep(toleranceOne, 0.0, (1.0 - edgeSoftnessOne) * maxValueOne);
        color = vec4(grayColor, color.a) * (1.0 - m) + color * m;
    }

    gl_FragColor = color;
}
]]


LeaveColor = {}

function LeaveColor:matchWithId(effectId)
    return 'KFM KSkr LeaveColor' == effectId
end

function LeaveColor.createWithId(effectId)
    if not LeaveColor:matchWithId(effectId) then
        return nil
    end
    local o = {
        drawer = {},
        program = {},
        width = 720,
        height = 1280
    }
    o = newObject(o, LeaveColor)
    o:init()
    return o;
end

function LeaveColor:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
    self.program = self.drawer:getProgram()
end

function LeaveColor:valueType(index)
    if index == 1 then
        -- AmountToDecolor
        return FM.AEValueType_OneDFloat
    elseif index == 2 then
        -- ColorOneToLeave
        return FM.AEValueType_ThreeD
    elseif index == 3 then
        -- ToleranceOne
        return FM.AEValueType_OneDFloat
    elseif index == 4 then
        -- EdgeSoftness
        return FM.AEValueType_OneDFloat
    elseif index == 5 then
        -- ColorTwoToLeave
        return FM.AEValueType_ThreeD
    elseif index == 6 then
        -- ToleranceTwo
        return FM.AEValueType_OneDFloat
    elseif index == 7 then
        -- ColorThreeToLeave
        return FM.AEValueType_ThreeD
    elseif index == 8 then
        -- ToleranceThree
        return FM.AEValueType_OneDFloat
    elseif index == 9 then
        -- ColorFourToLeave
        return FM.AEValueType_ThreeD
    elseif index == 10 then
        -- ToleranceFour
        return FM.AEValueType_OneDFloat
    elseif index == 11 then
        -- ColorFiveToLeave
        return FM.AEValueType_ThreeD
    elseif index == 12 then
        -- ToleranceFive
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function LeaveColor:updateValue(index, val1, val2, val3)
    self.program:bind()
    if index == 1 then
        -- AmountToDecolor
        self.program:sendUniformf('amountToDecolor', val1 * 0.01)
    elseif index == 2 then
        -- ColorOneToLeave
        self.program:sendUniformf('colorOneToLeave', val1, val2, val3)
    elseif index == 3 then
        -- ToleranceOne
        self.program:sendUniformf('toleranceOne', val1 * 0.01)
    elseif index == 4 then
        -- EdgeSoftness
        self.program:bind()
        self.program:sendUniformf('edgeSoftnessOne', val1 * 0.01)
    elseif index == 5 then
        -- ColorTwoToLeave
        self.program:sendUniformf('colorTwoToLeave', val1, val2, val3)
    elseif index == 6 then
        -- ToleranceTwo
        self.program:sendUniformf('toleranceTwo', val1 * 0.01)
    elseif index == 7 then
        -- ColorThreeToLeave
        self.program:sendUniformf('colorThreeToLeave', val1, val2, val3)
    elseif index == 8 then
        -- ToleranceThree
        self.program:sendUniformf('toleranceThree', val1 * 0.01)
    elseif index == 9 then
        -- ColorFourToLeave
        self.program:sendUniformf('colorFourToLeave', val1, val2, val3)
    elseif index == 10 then
        -- ToleranceFour
        self.program:sendUniformf('toleranceFour', val1 * 0.01)
    elseif index == 11 then
        -- ColorFiveToLeave
        self.program:sendUniformf('colorFiveToLeave', val1, val2, val3)
    elseif index == 12 then
        -- ToleranceFive
        self.program:sendUniformf('toleranceFive', val1 * 0.01)
    end

end

function LeaveColor:resize(width, height)

end

function LeaveColor:customResize(width, height)
    self.width = width
    self.height = height
end

function LeaveColor:render(outFBO, inputTex)
    local viewportSize = {}
    glGetIntegerv(GL_VIEWPORT, 4, viewportSize)
    self:customResize(viewportSize[3], viewportSize[4])

    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self.program:bind()
    self.drawer:drawTexture(inputTex)
end

function LeaveColor:onDestroy()

end
    