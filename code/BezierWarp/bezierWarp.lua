
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
attribute vec2 coord;
varying vec2 textureCoord;

void main()
{
    textureCoord = coord;
    gl_Position = vec4(position * 2.0 - 1.0, 0.0, 1.0);
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

void main() 
{
    gl_FragColor = texture2D(inputImageTexture, textureCoord);
}
]]

local buffers = {}
local vertices = {}
local coords = {}
local indices = {}

BezierWarp = {}

function BezierWarp:matchWithId(effectId)
    return 'KFM KSkr BezierWarp' == effectId
end

function BezierWarp.createWithId(effectId)
    if not BezierWarp:matchWithId(effectId) then
        return nil
    end
    local o = {
        program = {},
        vertexBuffer = 0,
        coordBuffer = 0,
        indexBuffer = 0,
        corners = {},
        anchors = {},
        currentWidth = 720,
        currentHeight = 1280,
        type = 1
    }
    o = newObject(o, BezierWarp)
    o:init()
    return o;
end

function BezierWarp:init()
    self.program = CGE.ProgramObject()
    self.program:bindAttribLocation('position', 0)
    self.program:bindAttribLocation('coord', 1)
    self.program:initWithShaderStrings(vs, fs)
    self.program:bind()
    self.program:sendUniformi('inputImageTexture', 0)

    glGenBuffers(3, buffers)
    self.vertexBuffer = buffers[1]
    self.coordBuffer = buffers[2]
    self.indexBuffer = buffers[3] 

    self.corners[1] = {0, 0}
    self.corners[2] = {1, 0}
    self.corners[3] = {1, 1}
    self.corners[4] = {0, 1}

    self.anchors[1] = {0, 1/3}
    self.anchors[2] = {1/3, 0}

    self.anchors[3] = {2/3, 0}
    self.anchors[4] = {1, 1/3}

    self.anchors[5] = {1, 2/3}
    self.anchors[6] = {2/3, 1}

    self.anchors[7] = {1/3, 1}
    self.anchors[8] = {0, 2/3}

    -- for i = 1, 4, 1 do
    --     self.anchors[i * 2 - 1] = self.corners[i] + (self.corners[(i + 3) % 5] - self.corners[i]) / 3
    --     self.anchors[i * 2 - 1] = self.corners[i] + (self.corners[(i + 3) % 5] - self.corners[i]) / 3
    --     self.anchors[i * 2] = self.corners[i] + (self.corners[(i + 1) % 5] - self.corners[i]) / 3
    --     self.anchors[i * 2] = self.corners[i] + (self.corners[(i + 1) % 5] - self.corners[i]) / 3
    -- end

    self:initBuffer()
end

function BezierWarp:bezierPoint(x0, x1, x2, x3, t)
    local cx = 3.0 * (x1 - x0) 
    local bx = 3.0 * (x2 - x1) - cx
    local ax = x3 - x0 - cx - bx

    local t2 = t * t
    local t3 = t2 * t

    return (ax * t3) + (bx * t2) + (cx * t) + x0
end

function BezierWarp:initBuffer()
    indices = {}
    coords = {}

    local w = 32
    local h = 32

    for i = 0, h, 1 do
        local heightStep = i / h
        for j = 0, w, 1 do 
            local widthStep = j / w 
            table.insert(coords, heightStep)
            table.insert(coords, widthStep)
        end 
    end
    local coordData = CGE.FloatBuffer:alloc(#coords)
    coordData:put(#coords, coords, 0)

    glBindBuffer(GL_ARRAY_BUFFER, self.coordBuffer)
    glBufferData(GL_ARRAY_BUFFER, #coords, coordData, GL_STATIC_DRAW)


    for i = 0, h - 1, 1 do
        local lineIndex0 = i * (w + 1)
        local lineIndex1 = (i + 1) * (w + 1) 
        for j = 0, w - 1, 1 do
            table.insert(indices, lineIndex0 + j)
            table.insert(indices, lineIndex0 + j + 1)
            table.insert(indices, lineIndex1 + j)
            table.insert(indices, lineIndex1 + j)
            table.insert(indices, lineIndex0 + j + 1)
            table.insert(indices, lineIndex1 + j + 1)
        end
    end
    local indexData = CGE.ShortBuffer:alloc(#indices)
    indexData:put(#indices, indices, 0)

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, self.indexBuffer)
    glBufferDataS(GL_ELEMENT_ARRAY_BUFFER, #indices, indexData, GL_STATIC_DRAW)
end

function BezierWarp:generateBuffer()
    --- 按照不同比例适配
    local param = {}
    param[1] = {1080, 1080}
    param[2] = {1080, 1440}
    param[3] = {1440, 1080}
    param[4] = {1080, 1920}
    param[5] = {1920, 1080}

    for i = 1, 4 do
        self.corners[i][1] = self.corners[i][1] * self.currentWidth / param[self.type][1]
        self.corners[i][2] = self.corners[i][2] * self.currentHeight / param[self.type][2]
    end
    for j = 1, 8 do
        self.anchors[j][1] = self.anchors[j][1] * self.currentWidth / param[self.type][1]
        self.anchors[j][2] = self.anchors[j][2] * self.currentHeight / param[self.type][2]
    end
    
    vertices = {}

    local w = 32
    local h = 32

    for i = 0, h, 1 do
        local heightStep = i / h
        for j = 0, w, 1 do 
            local widthStep = j / w 
            local start_x = self:bezierPoint(self.corners[1][1], self.anchors[1][1], self.anchors[8][1], self.corners[4][1], widthStep) 
            local end_x = self:bezierPoint(self.corners[2][1], self.anchors[4][1], self.anchors[5][1], self.corners[3][1], widthStep) 
            local start_y = self:bezierPoint(self.corners[1][2], self.anchors[1][2], self.anchors[8][2], self.corners[4][2], widthStep) 
            local end_y = self:bezierPoint(self.corners[2][2], self.anchors[4][2], self.anchors[5][2], self.corners[3][2], widthStep) 

            local x = self:bezierPoint(start_x, (self.anchors[2][1] - self.anchors[7][1]) * (1.0 - widthStep) + self.anchors[7][1], (self.anchors[3][1] - self.anchors[6][1]) * (1.0 - widthStep) + self.anchors[6][1], end_x, heightStep)
            local y = self:bezierPoint(start_y, (self.anchors[2][2] - self.anchors[7][2]) * (1.0 - widthStep) + self.anchors[7][2], (self.anchors[3][2] - self.anchors[6][2]) * (1.0 - widthStep) + self.anchors[6][2], end_y, heightStep)

            table.insert(vertices, x / self.currentWidth)
            table.insert(vertices, y / self.currentHeight)
        end 
    end
    local vData = CGE.FloatBuffer:alloc(#vertices)
    vData:put(#vertices, vertices, 0)

    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glBufferData(GL_ARRAY_BUFFER, #vertices, vData, GL_STATIC_DRAW)
end

function BezierWarp:valueType(index)
    if index == 1 then
        -- TopLeftVtx
        return FM.AEValueType_TwoD
    elseif index == 2 then
        -- TopLeftTan
        return FM.AEValueType_TwoD
    elseif index == 3 then
        -- TopRightTan
        return FM.AEValueType_TwoD
    elseif index == 4 then
        -- RightTopVtx
        return FM.AEValueType_TwoD
    elseif index == 5 then
        -- RightTopTan
        return FM.AEValueType_TwoD
    elseif index == 6 then
        -- RightDownTan
        return FM.AEValueType_TwoD
    elseif index == 7 then
        -- DownRightVtx
        return FM.AEValueType_TwoD
    elseif index == 8 then
        -- DownRightTan
        return FM.AEValueType_TwoD
    elseif index == 9 then
        -- DownLeftTan
        return FM.AEValueType_TwoD
    elseif index == 10 then
        -- LeftDownVtx
        return FM.AEValueType_TwoD
    elseif index == 11 then
        -- LeftDownTan
        return FM.AEValueType_TwoD
    elseif index == 12 then
        -- LeftTopTan
        return FM.AEValueType_TwoD
    elseif index == 13 then
        return FM.AEValueType_OneDInt
    end
    return FM.AEValueType_No_Value
end

function BezierWarp:updateValue(index, val1, val2, val3)
    self.program:bind()
    if index == 1 then
        -- TopLeftVtx
        self.corners[1] = {val1 , val2}
    elseif index == 2 then
        -- TopLeftTan
        self.anchors[2] = {val1, val2}
    elseif index == 3 then
        -- TopRightTan
        self.anchors[3] = {val1, val2}
    elseif index == 4 then
        -- RightTopVtx
        self.corners[2] = {val1, val2}
    elseif index == 5 then
        -- RightTopTan
        self.anchors[4] = {val1, val2}
    elseif index == 6 then
        -- RightDownTan
        self.anchors[5] = {val1, val2}
    elseif index == 7 then
        -- DownRightVtx
        self.corners[3] = {val1, val2}
    elseif index == 8 then
        -- DownRightTan
        self.anchors[6] = {val1, val2}
    elseif index == 9 then
        -- DownLeftTan
        self.anchors[7] = {val1, val2}
    elseif index == 10 then
        -- LeftDownVtx
        self.corners[4] = {val1, val2}
    elseif index == 11 then
        -- LeftDownTan
        self.anchors[8] = {val1, val2}
    elseif index == 12 then
        -- LeftTopTan
        self.anchors[1] = {val1, val2}
    elseif index == 13 then
        self.type = val1
    end
end

function BezierWarp:resize(width, height)
end

function BezierWarp:customResize(width, height)
	self.currentWidth = width
	self.currentHeight = height
end

function BezierWarp:render(outFBO, inputTex)
	local viewportSize = {}
    glGetIntegerv(GL_VIEWPORT, 4, viewportSize)
    self:customResize(viewportSize[3], viewportSize[4])

    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self:generateBuffer()

    self.program:bind()
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, inputTex)

    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0)

    glBindBuffer(GL_ARRAY_BUFFER, self.coordBuffer)
    glEnableVertexAttribArray(1)
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 0, 0)

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, self.indexBuffer)
    glDrawElements(GL_TRIANGLES, #indices, GL_UNSIGNED_SHORT, 0)
end

function BezierWarp:onDestroy()
    glDeleteBuffers(#buffers, buffers)
    glDeleteBuffers(1, {self.vertexBuffer})
end
    
