require('script/newShatter/class')
require('script/newShatter/delaunay')
require('script/newShatter/mat4')

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

    attribute vec2 position; // from -1 to 1
    attribute vec3 rs;
    attribute vec3 la;
    varying vec2 textureCoord;

    //uniform mat4 matWorld;
    //uniform mat4 matVP;

    uniform mat4 matProj;
    uniform vec2 canvasSize;

    #define pi 3.1415926

    mat4 MakeRotateMatrix(float pitch, float yaw, float roll)
    {
        float PI_180 = pi / 180.0;
        float cx = cos(pitch * PI_180);
        float sx = sin(pitch * PI_180);
        float cy = cos(yaw * PI_180);
        float sy = sin(yaw * PI_180);
        float cz = cos(roll * PI_180);
        float sz = sin(roll * PI_180);
        mat4 mat_table = mat4(cy * cz, sx * sy * cz + cx * sz, -cx * sy * cz + sx * sz, 0.0,
                         -cy * sz, -sx * sy * sz + cx * cz, cx * sy * sz + sx * cz, 0.0,
                         sy, -sx * cy, cx * cy, 0.0,
                         0.0, 0.0, 0.0, 1.0);
        return mat_table;
    }

    vec3 cgeCrossV3f(vec3 left, vec3 right)
    {
        return vec3(left[1] * right[2] - left[2] * right[1],
                     left[2] * right[0] - left[0] * right[2],
                     left[0] * right[1] - left[1] * right[0]);
    }

    mat4 makeLookAtMatrix(vec3 eye, vec3 center, vec3 up)
    {
        vec3 forward = normalize(eye - center);
        vec3 side = normalize(cgeCrossV3f(up, forward));
        vec3 upVector = cgeCrossV3f(forward, side);

        return mat4(side[0], upVector[0], forward[0], 0.0,
                    side[1], upVector[1], forward[1], 0.0,
                    side[2], upVector[2], forward[2], 0.0,
                    -dot(side, eye),
                    -dot(upVector, eye),
                    -dot(forward, eye),
                    1.0);
    }

    void main()
    {
        textureCoord = position * .5 + .5;

        vec2 texSize = canvasSize / 2.0;
        vec3 pos = vec3((position + la.xy / canvasSize) * texSize, 0.0);

        mat4 matWorld = MakeRotateMatrix(rs.x, rs.y, rs.z);
        mat4 matVP = matProj * makeLookAtMatrix(vec3(0.0, 0.0, la.z), vec3(0.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0));

        gl_Position = matVP * matWorld * vec4(pos, 1.0);
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
        vec4 color = texture2D(inputImageTexture, textureCoord);
        gl_FragColor = color;
    }
]]


local buffers = {}
local nVertices = 0
local tmpVertices = {}
local vertices = {}
local tmpIndices = {}
local indices = {}
local tbl_rs = {}

local TWO_PI = 6.2831852
local scatters = 0

NewShatter = {}

function NewShatter:matchWithId(effectId)
    return 'KFM KSkr NewShatter' == effectId
end

function NewShatter.createWithId(effectId)
    if not NewShatter:matchWithId(effectId) then
        return nil
    end
    local o = {
        program = {},
        ps = {},
        vertexBuffer = 0,
        indexBuffer = 0,
        rsBuffer = 0,
        width = 720,
        height = 1280,
        pitch = 0,
        yaw = 0,
        roll = 0,
        positionX = 0,
        positionY = 0,
        positionZ = 1,
        repetitions = 12,
        controShatter = 0,
        clickCenter = {0.0, 0.0},
        pattern = 1
    }
    o = newObject(o, NewShatter)
    o:init()
    return o;
end

function NewShatter:init()
    self.program = CGE.ProgramObject()
    self.program:bindAttribLocation('position', 0)
    self.program:bindAttribLocation('rs', 1)
    self.program:bindAttribLocation('la', 2)
    self.program:initWithShaderStrings(vs, fs)
    self.program:bind()
    self.program:sendUniformi('inputImageTexture', 0)

    self.matProjLoc = self.program:uniformLocation('matProj')
    --self.matWorldLoc = self.program:uniformLocation('matWorld')

    glGenBuffers(4, buffers)
    self.vertexBuffer = buffers[1]
    self.indexBuffer = buffers[2] 
    self.rsBuffer = buffers[3]
    self.laBuffer = buffers[4]

    self:triangulate()
    self:generateBuffer()
end


function NewShatter:valueType(index)
    if index == 1 then
        -- Repetitions
        return FM.AEValueType_OneDInt
    elseif index == 2 then
        -- ControPositionZ
        return FM.AEValueType_OneDFloat
    elseif index == 3 then
        -- RotationX
        return FM.AEValueType_OneDFloat
    elseif index == 4 then
        -- RotationY
        return FM.AEValueType_OneDFloat
    elseif index == 5 then
        -- RotationZ
        return FM.AEValueType_OneDFloat
    elseif index == 6 then
        -- PositionX
        return FM.AEValueType_OneDFloat
    elseif index == 7 then
        -- PositionY
        return FM.AEValueType_OneDFloat
    elseif index == 8 then
        -- PositionZ
        return FM.AEValueType_OneDFloat
    elseif index == 9 then
        -- Pattern
        return FM.AEValueType_OneDInt
    end
    return FM.AEValueType_No_Value
end

function NewShatter:MakeRotateMatrix(pitch, yaw, roll)
    local PI_180 = math.pi / 180.0
    local cx = math.cos(pitch * PI_180);
    local sx = math.sin(pitch * PI_180);
    local cy = math.cos(yaw * PI_180);
    local sy = math.sin(yaw * PI_180);
    local cz = math.cos(roll * PI_180);
    local sz = math.sin(roll * PI_180);
    local mat_table = {cy * cz, sx * sy * cz + cx * sz, -cx * sy * cz + sx * sz, 0.0,
                     -cy * sz, -sx * sy * sz + cx * cz, cx * sy * sz + sx * cz, 0.0,
                     sy, -sx * cy, cx * cy, 0.0,
                     0.0, 0.0, 0.0, 1.0 }
    return mat_table
end

function NewShatter:updateValue(index, val1, val2, val3)
    self.program:bind()
    if index == 1 then
        -- Repetitions
        self.repetitions = val1
    elseif index == 2 then
        -- ControShatter
        self.controShatter = val1
    elseif index == 3 then
        -- RotationX
        self.pitch = val1
        --local matrix = self:MakeRotateMatrix(math.modf(self.pitch, 100.0), math.modf(self.yaw, 100.0), math.modf(self.roll, 100.0))
        --glUniformMatrix4fv(self.matWorldLoc, 1, 0, matrix)
    elseif index == 4 then
        -- RotationY
        self.yaw = val1
        --local matrix = self:MakeRotateMatrix(math.modf(self.pitch, 100.0), math.modf(self.yaw, 100.0), math.modf(self.roll, 100.0))
        --glUniformMatrix4fv(self.matWorldLoc, 1, 0, matrix)
    elseif index == 5 then
        -- RotationZ
        self.roll = val1
        --local matrix = self:MakeRotateMatrix(math.modf(self.pitch, 100.0), math.modf(self.yaw, 100.0), math.modf(self.roll, 100.0))
        --glUniformMatrix4fv(self.matWorldLoc, 1, 0, matrix)
    elseif index == 6 then
        -- PositionX
        self.positionX = val1
    elseif index == 7 then
        -- PositionY
        self.positionY = val1
    elseif index == 8 then
        -- PositionZ
        self.positionZ = val1
    elseif index == 9 then
        -- Pattern
        self.pattern = val1
    end
end

function NewShatter:randomRange(min, max) 
    return min + (max - min) * math.random()
end

function NewShatter:clamp(x, min, max)  
    if x < min then
        return min
    end
    if x > max then
        return max
    end
    return x
end

function NewShatter:sign(x) 
    if x < 0 then
        return -1
    else 
        return 1
    end
end

function NewShatter:triangulate()
    tmpVertices = {}
    local rings = {}
    table.insert(rings, {0.2, self.repetitions})
    table.insert(rings, {0.4, self.repetitions})
    table.insert(rings, {0.75, self.repetitions})
    table.insert(rings, {3.0, self.repetitions})

    local centerX = self.clickCenter[1]
    local centerY = self.clickCenter[2]
    --table.insert(tmpVertices, {centerX, centerY})

    for i = 1, #rings do
        for j = 1, rings[i][2] do
            local x = math.cos((j / rings[i][2]) * TWO_PI) * rings[i][1] + centerX + self:randomRange(-rings[i][1] * 0.25, rings[i][1] * 0.25)
            local y = math.sin((j / rings[i][2]) * TWO_PI) * rings[i][1] + centerY + self:randomRange(-rings[i][1] * 0.25, rings[i][1] * 0.25)

            x = self:clamp(x, -1, 1)
            y = self:clamp(y, -1, 1)

            table.insert(tmpVertices, {x, y})
            -- print('----------vertice' .. x .. '-----------' .. y)
        end
    end

    -- table.insert(tmpVertices, {0.5, 0.5})
    -- table.insert(tmpVertices, {0.5, -0.5})
    -- table.insert(tmpVertices, {0.0, 0.0})
    -- table.insert(tmpVertices, {-0.5, -0.5})
    -- table.insert(tmpVertices, {-0.5, 0.5})

    nVertices = #tmpVertices
    tmpIndices = {}
    tmpIndices = Delaunay:triangulate(tmpVertices)
end


function NewShatter:computeCentroid(p1, p2, p3)
    local a = (p1[1] + p2[1] + p3[1]) / 3
    local b = (p1[2] + p2[2] + p3[2]) / 3
    return {a, b}
end

function NewShatter:generateBuffer()

    -- ----------------------------vertices
    -- for i = 1, nVertices do
    --     table.insert(vertices, tmpVertices[i][1])
    --     table.insert(vertices, tmpVertices[i][2])
    -- end

    -- local vData = CGE.FloatBuffer:alloc(#vertices)
    -- vData:put(#vertices, vertices, 0)

    -- glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    -- glBufferData(GL_ARRAY_BUFFER, #vertices, vData, GL_STATIC_DRAW)

    -- for i = 1, #vertices do
    --     print('myVer---------------******' .. vertices[i])
    -- end


    -- -----------------------------indices
    -- for i = #tmpIndices, 1, -1 do
    --     table.insert(indices, tmpIndices[i][1] - 1)
    --     table.insert(indices, tmpIndices[i][2] - 1)
    --     table.insert(indices, tmpIndices[i][3] - 1)
    -- end

    -- local indexData = CGE.ShortBuffer:alloc(#indices)
    -- indexData:put(#indices, indices, 0)

    -- glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, self.indexBuffer)
    -- glBufferDataS(GL_ELEMENT_ARRAY_BUFFER, #indices, indexData, GL_STATIC_DRAW)

    -- for i = 1, #indices do
    --     print('myIndices---------------******' .. indices[i])
    -- end


    -----------------------------------new vertices
    vertices = {}
    for i = 1, #tmpIndices do
        for j = 1, #tmpIndices[i] do
            local curVer = tmpVertices[tmpIndices[i][j]]
            table.insert(vertices, curVer[1])
            table.insert(vertices, curVer[2])
        end
    end

    local vData = CGE.FloatBuffer:alloc(#vertices)
    vData:put(#vertices, vertices, 0)

    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glBufferData(GL_ARRAY_BUFFER, #vertices, vData, GL_STATIC_DRAW)

    -- for i = 1, #vertices do
    --     print('myVer---------------******' .. vertices[i] .. '&&&&&&&&&&' .. #vertices)
    -- end


    -----------------------------------new index
    indices = {}
    for i = 1, 3 * #tmpIndices do
        table.insert(indices, i - 1)
    end

    local indexData = CGE.ShortBuffer:alloc(#indices)
    indexData:put(#indices, indices, 0)

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, self.indexBuffer)
    glBufferDataS(GL_ELEMENT_ARRAY_BUFFER, #indices, indexData, GL_STATIC_DRAW)

    -- for i = 1, #indices do
    --     print('myIndices---------------******' .. indices[i] .. '&&&&&&&&&' .. #indices)
    -- end
end

function NewShatter:resize(width, height)
 
end

-- function NewShatter:customResize(width, height)
--     self.width = width
--     self.height = height

--     self.program:bind()
--     self.program:sendUniformf('canvasSize', width, height)

--     local fovy = math.pi / 3
--     local proj = makePerspective(fovy, width / height, 0.1, 5000)
--     glUniformMatrix4fv(self.matProjLoc, 1, 0, proj_numTable)   


--     local z = height / (math.tan(fovy / 2) * 2)
--     local view = makeLookAt(vec3(0, 0, z * self.positionZ), vec3(self.positionX, self.positionY, 0), vec3(0, 1, 0))

--     proj = proj * view

--     local proj_numTable = {proj.m00, proj.m01, proj.m02, proj.m03,
--                            proj.m10, proj.m11, proj.m12, proj.m13,
--                            proj.m20, proj.m21, proj.m22, proj.m23,
--                            proj.m30, proj.m31, proj.m32, proj.m33}

--     self.program:bind()
--     glUniformMatrix4fv(self.matVPLoc, 1, 0, proj_numTable)   
-- end


function NewShatter:customResize(width, height)
    self.width = width
    self.height = height

    self.program:bind()
    self.program:sendUniformf('canvasSize', width, height)

    local fovy = math.pi / 3
    local proj = makePerspective(fovy, width / height, 0.1, 5000)

    local proj_numTable = {proj.m00, proj.m01, proj.m02, proj.m03,
                           proj.m10, proj.m11, proj.m12, proj.m13,
                           proj.m20, proj.m21, proj.m22, proj.m23,
                           proj.m30, proj.m31, proj.m32, proj.m33}

    glUniformMatrix4fv(self.matProjLoc, 1, 0, proj_numTable)   
end

function NewShatter:shatter()
    -----------------------------shatter
    tbl_rs = {}

    local tbl_lookat = {}
    local fovy = math.pi / 3
    local z = self.height / (math.tan(fovy / 2) * 2)

    for k = 1, #tmpIndices do
        local centroid = self:computeCentroid(tmpVertices[tmpIndices[k][1]], tmpVertices[tmpIndices[k][2]], tmpVertices[tmpIndices[k][3]])
        local dx = centroid[1] - self.clickCenter[1]
        local dy = centroid[2] - self.clickCenter[2]
        if math.abs(dx) < 0.03 then
            dx = self:sign(dx) * 0.03
        end
        if math.abs(dy) < 0.03 then
            dy = self:sign(dy) * 0.03
        end

        local d = math.sqrt(dx * dx + dy * dy)
        local rx = math.modf(self.pitch * math.cos(math.modf(k, 10.0) / #tmpIndices * self.repetitions * TWO_PI), 100.0) 
        local ry = math.modf(self.yaw * math.cos(math.modf(k, 10.0) / #tmpIndices * self.repetitions * TWO_PI), 100.0) 
        local rz = math.modf(self.roll * math.cos(math.modf(k, 10.0) / #tmpIndices * self.repetitions * TWO_PI), 100.0)

        for _ = 1, 3 do
            table.insert(tbl_rs, rx)
            table.insert(tbl_rs, ry)
            table.insert(tbl_rs, rz)
        end

        for _ = 1, 3 do
            table.insert(tbl_lookat, self.positionX * dx)
            table.insert(tbl_lookat, self.positionY * dy)
            if self.pattern == 1 then
                table.insert(tbl_lookat, (self.positionZ + 1) * z - self:clamp(self.controShatter * 0.1 * math.sqrt(dx * self.width * dx * self.width + dy * self.height * dy * self.height), 0.0, z * (self.positionZ + 1)))
            elseif self.pattern == 2 then
                table.insert(tbl_lookat, (self.positionZ + 1) * z - self:clamp(self.controShatter * 0.1 * (math.sqrt(self.width * self.width + self.height * self.height) - math.sqrt(dx * self.width * dx * self.width + dy * self.height * dy * self.height)), 0.0, z * (self.positionZ + 1)))
            end
        end
    end

    local rsData = CGE.FloatBuffer:alloc(#tbl_rs)
    rsData:put(#tbl_rs, tbl_rs, 0)

    glBindBuffer(GL_ARRAY_BUFFER, self.rsBuffer)
    glBufferData(GL_ARRAY_BUFFER, #tbl_rs, rsData, GL_STREAM_DRAW)


    local lookatData = CGE.FloatBuffer:alloc(#tbl_lookat)
    lookatData:put(#tbl_lookat, tbl_lookat, 0)

    glBindBuffer(GL_ARRAY_BUFFER, self.laBuffer)
    glBufferData(GL_ARRAY_BUFFER, #tbl_lookat, lookatData, GL_STREAM_DRAW)
end


function NewShatter:render(outFBO, inputTex)
    if scatters ~= self.repetitions then
        self:triangulate()
        self:generateBuffer()
        scatters = self.repetitions
    end

    local viewportSize = {}
    glGetIntegerv(GL_VIEWPORT, 4, viewportSize)
    self:customResize(viewportSize[3], viewportSize[4])
    self:shatter()

    glBindFramebuffer(GL_FRAMEBUFFER, outFBO)
    self.program:bind()

    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, inputTex)

    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0)

    glBindBuffer(GL_ARRAY_BUFFER, self.rsBuffer)    
    glEnableVertexAttribArray(1)
    glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 0, 0)

    glBindBuffer(GL_ARRAY_BUFFER, self.laBuffer)    
    glEnableVertexAttribArray(2)
    glVertexAttribPointer(2, 3, GL_FLOAT, GL_FALSE, 0, 0)

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, self.indexBuffer)
    glDrawElements(GL_TRIANGLES, #indices, GL_UNSIGNED_SHORT, 0)
end

function NewShatter:onDestroy()
    glDeleteBuffers(#buffers, buffers)
end
    




