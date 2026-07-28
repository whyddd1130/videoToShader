local function newObject(o, class)
    class.__index = class
    return setmetatable(o, class)
end

local s_vsh = [[
attribute vec2 vPosition;
varying vec2 vUV0;
void main()
{
    gl_Position = vec4(vPosition, 0.0, 1.0);
    //An opportunism code. Do not use it unless you know what it means.
    vUV0 = (vPosition.xy + 1.0) / 2.0;
}
]]

local s_fsh = [[
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

    uniform sampler2D inputImageTexture;
    uniform float curvature;
    uniform float shift;

    varying vec2 vUV0;

    void main()
    {
        vec2 uv=vUV0;
        
        uv.x-=((uv.y-1.0)*(uv.y-1.0)*curvature);

        uv.x-=shift;
    
        if(uv.x>=0.0)
        {
            gl_FragColor = texture2D(inputImageTexture, uv);
        }
        else
        {
            gl_FragColor=vec4(0.0,0.0,0.0,1.0);
        }

    }
]]

Tornado = {}

function Tornado:matchWithId(effectId)
    return 'KFM KSkr Tornado' == effectId
end

function Tornado.createWithId(effectId)
    if not Tornado:matchWithId(effectId) then
        return nil
    end
    local o = {
        program = {},
        vertexBuffer = 0
    }
    o = newObject(o, Tornado)
    o:init()
    return o;
end

function Tornado:init()
    local buffer = {}
    glGenBuffers(1, buffer)
    self.vertexBuffer=buffer[1]

    local vertexBufferData = CGE.FloatBuffer:alloc(8)
    vertexBufferData:put(8, { -1, -1, 1, -1, -1, 1, 1, 1}, 0)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glBufferData(GL_ARRAY_BUFFER, 8, vertexBufferData, GL_STATIC_DRAW)

    self.program = CGE.ProgramObject()
    self.program:bindAttribLocation("vPosition", 0)
    self.program:initWithShaderStrings(s_vsh, s_fsh)
end

function Tornado:onDestroy()
    glDeleteBuffers(1, {self.vertexBuffer})
end

function Tornado:valueType(index)
    if index == 1 then
        --
        return FM.AEValueType_OneDFloat
    elseif index == 2 then
        --
        return FM.AEValueType_OneDFloat
    end
end

function Tornado:updateValue(index, val1, val2, val3)
    self.program:bind()
    if index == 1 then
        --
        self.program:sendUniformf("curvature", val1)
    elseif index == 2 then
        --
        self.program:sendUniformf("shift", val1)         
    end
end

function Tornado:resize(width, height)
    
end

function Tornado:render(outFBO, inputTex)
    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0)
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, inputTex)
    self.program:bind()
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)
end
