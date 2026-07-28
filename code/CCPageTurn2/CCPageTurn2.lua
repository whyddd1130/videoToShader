
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

#define pi 3.1415926

uniform vec2  iResolution;
uniform vec2 iMouse;
uniform int uCornerControls;
uniform float uRadius;
uniform float uLight;
uniform float uBackOpacity;

vec4 turnPage(vec2 fragCoord)
{
    vec4 color = texture2D(inputImageTexture, fragCoord);
    float aspect = iResolution.x / iResolution.y;
    vec2 uv = fragCoord * vec2(aspect, 1.);

    vec2 mouse = iMouse.xy  * vec2(aspect, 1.) / iResolution.xy;
    vec2 mouseDir = vec2(0.0, 0.0);
    vec2 origin = vec2(0.0, 0.0);

    if(uCornerControls == 1)
    {
        if(iMouse.x <= iResolution.x && iMouse.y <= iResolution.y)
        {
            mouseDir = normalize(iResolution.xy - iMouse.xy);
            origin = mouse - mouseDir;
        }
    }
    if(uCornerControls == 2)
    {
        if(iMouse.x <= iResolution.x && iMouse.y >= 0.0)
        {
            mouseDir = normalize(vec2(iResolution.x, 0.0) - iMouse.xy);
            origin = mouse - mouseDir;
        }
    }
    if(uCornerControls == 3)
    {
        if(iMouse.x >= 0.0 && iMouse.y <= iResolution.y)
        {
            mouseDir = normalize(vec2(0.0, iResolution.y) - iMouse.xy);
            origin = mouse - mouseDir;
        }
        
    }
    if(uCornerControls == 4)
    {
        if(iMouse.x >= 0.0 && iMouse.y >= 0.0)
        {
            mouseDir = normalize(vec2(0.0, 0.0) - iMouse.xy);
            origin = mouse - mouseDir;
        }
    }
    float mouseDist=length(mouse-origin);
    float proj = dot(uv - origin, mouseDir);
    float dist = proj - mouseDist;
    vec2 linePoint = uv - dist * mouseDir;

    if (dist >= 0. &&dist<= uRadius)
    {
        float theta = asin(dist / uRadius);

        vec2 p2 = linePoint + mouseDir * (3.14159 - theta) * uRadius;
        vec2 p1 = linePoint + mouseDir * theta * uRadius;
        uv = (p2.x <= aspect && p2.y <= 1. && p2.x > 0. && p2.y > 0.) ? p2 : p1;
        color = texture2D(inputImageTexture, uv * vec2(1. / aspect, 1.));

        vec4 color2;
        if(p2.x <= aspect && p2.y <= 1. && p2.x > 0. && p2.y > 0.)
        {
            vec4 color1=texture2D(inputImageTexture, p1 * vec2(1. / aspect, 1.));
            color2=texture2D(inputImageTexture, p2 * vec2(1. / aspect, 1.));
            //color2 *= uBackOpacity;
            color = color1*(1.0-color2.a)+color2;
        }
        if(uv.x==p2.x &&uv.y==p2.y )
        {
            dist=dist-uRadius/2.0;
            float mdis=abs(2.0*dist/uRadius);
            color += uLight*pow(1.0-mdis, 1.5) * uBackOpacity * step(0.01, color2.a);
        }
    }
    else if(dist<0.)
    {
        vec2 p = linePoint + mouseDir * (abs(dist) + 3.14159 * uRadius);
        if((p.x <= aspect && p.y <= 1. && p.x > 0. && p.y > 0.))
        {
            vec4 color1 = texture2D(inputImageTexture, uv * vec2(1. / aspect, 1.));
            vec4 color2 = texture2D(inputImageTexture, p * vec2(1. / aspect, 1.));
            color2 *= uBackOpacity;
            color = color1 * (1.0 - color2.a) + color2;
        }
    }
    else
    {
        color = vec4(0.0, 0.0, 0.0, 0.0);
    }
    return color;
}
void main()
{
    gl_FragColor = turnPage(textureCoord);
}
]]

CCPageTurn2 = {}

function CCPageTurn2:matchWithId(effectId)
    return 'KFM KSkr CCPageTurn2' == effectId
end

function CCPageTurn2.createWithId(effectId)
    if not CCPageTurn2:matchWithId(effectId) then
        return nil
    end
    local o = {
        --drawer = {}
        program = {},
        vertexBuffer = 0
    }
    o = newObject(o, CCPageTurn2)
    o:init()
    return o;
end

function CCPageTurn2:init()
    --self.drawer = CGE.TextureDrawer:createWithShader(vs, fs)
    local buffer = {}
    glGenBuffers(1, buffer)
    self.vertexBuffer=buffer[1]

    local vertexBufferData = CGE.FloatBuffer:alloc(8)
    vertexBufferData:put(8, { -1, -1, 1, -1, -1, 1, 1, 1}, 0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glBufferData(GL_ARRAY_BUFFER, 8, vertexBufferData, GL_STATIC_DRAW)

    self.program = CGE.ProgramObject()
    self.program:bindAttribLocation("vPosition", 0)
    self.program:initWithShaderStrings(vs, fs)
end

function CCPageTurn2:valueType(index)
    if index == 1 then
        -- FoldPosition
        return FM.AEValueType_TwoD
    elseif index == 2 then
        -- CornerControls
        -- Bottom Right <--->  1
        -- Top Right <--->  2
        -- Bottom Left <--->  3
        -- Top Left <--->  4
        return FM.AEValueType_OneDInt
    elseif index == 3 then
        -- FoldRadius
        return FM.AEValueType_OneDFloat
    elseif index == 4 then
        -- LightDirection
        return FM.AEValueType_OneDFloat
    elseif index == 5 then
        -- BackOpacity
        return FM.AEValueType_OneDFloat
    end
    return FM.AEValueType_No_Value
end

function CCPageTurn2:updateValue(index, val1, val2, val3)
    -- local program = self.drawer:getProgram()
    -- program:bind()
    self.program:bind()
    if index == 1 then
        --vec2 Fold Position
        self.program:sendUniformf("iMouse", val1, val2)
    elseif index==2 then
        --CornerControls
        -- Bottom Right <--->  1
        -- Top Right <--->  2
        -- Bottom Left <--->  3
        -- Top Left <--->  4
        self.program:sendUniformi("uCornerControls", val1)
    elseif index == 3 then
        --Fold Radius
        self.program:sendUniformf("uRadius", val1)
    elseif index == 4 then
        --Light Direction
        self.program:sendUniformf("uLight", val1)
    elseif index == 5 then
        --Back Opacity
        self.program:sendUniformf("uBackOpacity", val1)
    end
end

function CCPageTurn2:resize(width, height)
    self.program:bind()
    self.program:sendUniformf("iResolution", width, height)
end

function CCPageTurn2:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, inputTex)
    self.program:bind()
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)
end

function CCPageTurn2:onDestroy()
    glDeleteBuffers(1, {self.vertexBuffer})
end
    