
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

uniform float fov;
uniform int reverseLens;
uniform int fovOrientation;
uniform vec2 viewCenter;
uniform vec2 imageSize;

const float PI = 3.1415926;

float getF(float h, float fov)
{
    return (h / 2.0) / (tan(fov / 2.0));
}

void main() 
{
    float dis = distance(textureCoord * imageSize, viewCenter);
    
    //计算焦距
    float f = getF(imageSize.x, fov / 180.0 * PI);
    if (fovOrientation == 1)
    {
        f = getF(imageSize.x, fov / 180.0 * PI);
    }
    else if (fovOrientation == 2)
    {
        f = getF(imageSize.y, fov / 180.0 * PI);
    }
    else if (fovOrientation == 3)
    {
        f = getF(distance(vec2(0.0), imageSize), fov / 180.0 * PI);
    }

    float offset_x = textureCoord.x - viewCenter.x / imageSize.x;
    float offset_y = textureCoord.y - viewCenter.y / imageSize.y;

    if(reverseLens == 1 && fov > 0.0)
    {
        float theta = asin(dis / -f);
        float offset = -f * tan(theta) / cos(theta);

        offset_x = offset * abs(textureCoord.x * imageSize.x - viewCenter.x) / dis;
        offset_y = offset * abs(textureCoord.y * imageSize.y - viewCenter.y) / dis;

        if (textureCoord.x < viewCenter.x / imageSize.x)
        {
            offset_x = -1. * offset_x;
        }
        if (textureCoord.y < viewCenter.y / imageSize.y) 
        {
            offset_y = -1. * offset_y;
        }

        offset_x = offset_x / imageSize.x;
        offset_y = offset_y / imageSize.y;
    }
    if(reverseLens == 2 && fov > 0.0) //反转镜头扭曲
    {
        float theta = atan(dis, f);
        float offset = f * sin(theta);
        offset_x = offset * abs(textureCoord.x * imageSize.x - viewCenter.x) / dis;
        offset_y = offset * abs(textureCoord.y * imageSize.y - viewCenter.y) / dis;

        if (textureCoord.x < viewCenter.x / imageSize.x) 
        {
            offset_x = -offset_x;
        }
        if (textureCoord.y < viewCenter.y / imageSize.y) 
        {
            offset_y = -offset_y;
        }

        offset_x = offset_x / imageSize.x;
        offset_y = offset_y / imageSize.y;
    }

    vec2 nUv = viewCenter / imageSize + vec2(offset_x, offset_y);
    vec2 lt = step(vec2(0.0, 0.0), nUv);
    vec2 rb = step(nUv, vec2(1.0, 1.0));
    gl_FragColor = mix(vec4(0.0), texture2D(inputImageTexture, nUv), step(2.0, dot(lt, rb)));
}
]]

OpticsCompensation = {}

function OpticsCompensation:matchWithId(effectId)
    return 'KFM KSkr OpticsCompensation' == effectId
end

function OpticsCompensation.createWithId(effectId)
    if not OpticsCompensation:matchWithId(effectId) then
        return nil
    end
    local o = {
        drawer = {},
        program = {}
    }
    o = newObject(o, OpticsCompensation)
    o:init()
    return o;
end

function OpticsCompensation:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
    self.program = self.drawer:getProgram()
end

function OpticsCompensation:valueType(index)
    if index == 1 then
        -- FOV
        return FM.AEValueType_OneDFloat
    elseif index == 2 then
        -- ReverseLens
        return FM.AEValueType_OneDInt
    elseif index == 3 then
        -- FovOrientation
        return FM.AEValueType_OneDInt
    elseif index == 4 then
        -- ViewCenter
        return FM.AEValueType_TwoD
    end
    return FM.AEValueType_No_Value
end

function OpticsCompensation:updateValue(index, val1, val2, val3)
    self.program:bind()
    if index == 1 then
        -- FOV
        self.program:sendUniformf("fov", val1)
    elseif index == 2 then
        -- ReverseLens
        -- val1 is a index(starts with 1, not 0) of [No | Yes]
        self.program:sendUniformi("reverseLens", val1)
    elseif index == 3 then
        -- FovOrientation
        -- val1 is a index(starts with 1, not 0) of [Horizontal | Vertical | Diagonal]
        self.program:sendUniformi("fovOrientation", val1)
    elseif index == 4 then
        -- ViewCenter
        self.program:sendUniformf("viewCenter", val1, val2)
    end

end

function OpticsCompensation:resize(width, height)
    self.program:bind()
    self.program:sendUniformf("imageSize", width, height)
end

function OpticsCompensation:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self.drawer:drawTexture(inputTex)
end

function OpticsCompensation:onDestroy()
end
    