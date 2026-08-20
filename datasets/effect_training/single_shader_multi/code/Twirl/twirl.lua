
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


const float PI = 3.1415926535898;
uniform sampler2D inputImageTexture;
uniform vec2 _mainTexSize;
uniform float _angle;
uniform float _radius;
uniform vec2  _center;
uniform int _tile;

varying vec2 textureCoord;
void main()
{
    vec2 tc= textureCoord * _mainTexSize;
    vec2 dir = tc - _center;
    float dist = length(dir);
    float radius = max(_mainTexSize.x, _mainTexSize.y) * _radius;
    float percent = (radius - dist) / radius;
    float theta = 1.5 * percent * percent * radians(_angle);
    float sinv = sin(theta);
    float cosv = cos(theta);
    vec2 rotateDir = vec2(dot(dir, vec2(cosv, -sinv)), dot(dir, vec2(sinv, cosv)));
    if(dist < radius)
    {
        dir = rotateDir;
    }
    tc = dir + _center;
    tc /= _mainTexSize;

    if(_tile > 0)
    {
        if(tc.x < 0.0) tc.x = -tc.x;
        if(tc.x > 1.0) tc.x = 2.0 - tc.x;
        if(tc.y < 0.0) tc.y = -tc.y;
        if(tc.y > 1.0) tc.y = 2.0 - tc.y;
    }

    gl_FragColor = texture2D(inputImageTexture, tc);
}
]]

Twirl = {}

function Twirl:matchWithId(effectId)
    return 'KFM KSkr Twirl' == effectId
end

function Twirl.createWithId(effectId)
    if not Twirl:matchWithId(effectId) then
        return nil
    end
    local o = {
        drawer = {},
        program = {}
    }
    o = newObject(o, Twirl)
    o:init()
    return o;
end

function Twirl:init()
    self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
    self.program = self.drawer:getProgram()
end

function Twirl:valueType(index)
    if index == 1 then
        -- twirlAngle
        return FM.AEValueType_OneDFloat
    elseif index == 2 then
        -- twirlRadius
        return FM.AEValueType_OneDFloat
    elseif index == 3 then
        -- twirlCenter
        return FM.AEValueType_TwoD
    elseif index == 4 then
        -- twirlTile
        return FM.AEValueType_OneDInt
    end
    return FM.AEValueType_No_Value
end

function Twirl:updateValue(index, val1, val2, val3)
    self.program:bind()
    if index == 1 then
        -- twirlAngle
        self.program:sendUniformf("_angle", val1)
    elseif index == 2 then
        -- twirlRadius
        self.program:sendUniformf("_radius", val1 / 100)
    elseif index == 3 then
        -- twirlCenter
        self.program:sendUniformf("_center", val1, val2)
    elseif index == 4 then
        -- twirlTile
        self.program:sendUniformi("_tile", val1)
    end

end

function Twirl:resize(width, height)
    self.program:bind();
    self.program:sendUniformf("_mainTexSize", width, height)
end

function Twirl:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self.drawer:drawTexture(inputTex)
end

function Twirl:onDestroy()
end
    
