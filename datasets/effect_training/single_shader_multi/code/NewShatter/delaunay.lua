require('script/newShatter/class')

Delaunay = class()

local EPSILON = 1.0 / 1048576.0
local open = {}
local closed = {}
local edges = {}

function Delaunay:supertriangle(vertices)
  local minX, minY = vertices[1][1], vertices[1][2]
  local maxX, maxY = minX, minY

  for i = 1, #vertices do
    if vertices[i][1] < minX then minX = vertices[i][1] end
    if vertices[i][2] < minY then minY = vertices[i][2] end
    if vertices[i][1] > maxX then maxX = vertices[i][1] end
    if vertices[i][2] > maxY then maxY = vertices[i][2] end

    --print('&&&&&&&&&&'.. vertices[i][1])
  end

  local dx, dy = (maxX - minX), (maxY - minY)
  local deltaMax = math.max(dx, dy)
  local midx, midy = minX + dx * 0.5, minY + dy * 0.5

  local superVertices = {}
  table.insert(superVertices, {midx - 20 * deltaMax, midy - 10 * deltaMax})
  table.insert(superVertices, {midx, midy + 20 * deltaMax})
  table.insert(superVertices, {midx + 20 * deltaMax, midy - 10 * deltaMax})

  return superVertices
end


function Delaunay:circumcircle(vertices, i, j, k)
  local x1 = vertices[i][1]
  local y1 = vertices[i][2]
  local x2 = vertices[j][1]
  local y2 = vertices[j][2]
  local x3 = vertices[k][1]
  local y3 = vertices[k][2]

  local fabsy1y2 = math.abs(y1 - y2)
  local fabsy2y3 = math.abs(y2 - y3)

  local xc, yc, m1, m2, mx1, mx2, my1, my2, dx, dy;

  if fabsy1y2 < EPSILON and fabsy2y3 < EPSILON then

  end

  if fabsy1y2 < EPSILON then
    m2 = -((x3 - x2) / (y3 - y2))
    mx2 = (x2 + x3) / 2.0
    my2 = (y2 + y3) / 2.0
    xc  = (x2 + x1) / 2.0
    yc  = m2 * (xc - mx2) + my2
  elseif fabsy2y3 < EPSILON then
    m1  = -((x2 - x1) / (y2 - y1))
    mx1 = (x1 + x2) / 2.0
    my1 = (y1 + y2) / 2.0
    xc  = (x3 + x2) / 2.0
    yc  = m1 * (xc - mx1) + my1
  else
    m1  = -((x2 - x1) / (y2 - y1))
    m2  = -((x3 - x2) / (y3 - y2))
    mx1 = (x1 + x2) / 2.0
    mx2 = (x2 + x3) / 2.0
    my1 = (y1 + y2) / 2.0
    my2 = (y2 + y3) / 2.0
    xc  = (m1 * mx1 - m2 * mx2 + my2 - my1) / (m1 - m2);
    if fabsy1y2 > fabsy2y3 then
      yc = m1 * (xc - mx1) + my1
    else
      yc = m2 * (xc - mx2) + my2
    end
  end

  dx = x2 - xc
  dy = y2 - yc

  return {i, j, k, xc, yc, dx * dx + dy * dy}
end


function Delaunay:dedup(edges)
  local a, b
  local j = #edges
  --print('edge_count---'.. #edges)

  -- for kk = #edges, 1 , -1 do
  --     print('edgeData---'.. edges[kk][1] .. '----------' .. edges[kk][2])
  -- end

  while(j > 0)
    do
      a = edges[j]
      --print('j============'.. j)

      for k = j - 1, 1, -1 do
        b = edges[k]
        --print('k============'.. k)
        if (a[1] == b[1] and a[2] == b[2]) or (a[1] == b[2] and a[2] == b[1]) then
          table.remove(edges, j)
          --print('edge_Size11---'.. #edges)
          table.remove(edges, k)
          --print('edge_Size22---'.. #edges)
          j = j - 1
          break
        end
      end

      j = j - 1
    end

  --print('edge_count_end---'.. #edges)
end


--- triangulate
function Delaunay:triangulate(vertices)
  local nVertices = #vertices

  -- print('num vertex' .. nVertices)

  if nVertices < 3 then
  end

  --- sorted by the vertices' x-position
  local indices = {}
  for i = 1, nVertices do
    table.insert(indices, i)
  end

  table.sort(indices, function(i, j)
    return vertices[i][1] > vertices[j][1]
  end)

  for i = 1, nVertices do
    --print('sort indices'.. indices[i])
  end

  --- find the vertices of the supertriangle
  local superVertices = self:supertriangle(vertices)
  for i = 1, #superVertices do
    table.insert(vertices, {superVertices[i][1], superVertices[i][2]})

    -- print('superVertices' .. superVertices[i][1] .. '-------*' .. superVertices[i][2])
  end
  
  --- Initialize the open list
  open = {}
  closed = {}
  table.insert(open, self:circumcircle(vertices, nVertices + 1, nVertices + 2, nVertices + 3))


  --- Incrementally add each vertex to the mesh
  for i = #indices, 1, -1 do
    local c = indices[i]
    --print('openSIze******' .. #open)
    edges = {}

    --- For each open triangle, check to see if the current point is inside it's circumcircle. If it is, remove the triangle and add it's edges to an edge list
    for j = #open, 1, -1 do
      local dx = vertices[c][1] - open[j][4]
      local dy = vertices[c][2] - open[j][5]
      if dx > 0.0 and dx * dx > open[j][6] then  ---If this point is to the right of this triangle's circumcircle, then this triangle should never get checked again. Remove it from the open list, add it to the closed list, and skip. */
        table.insert(closed, open[j])
        table.remove(open, j)
        --print('remove----' .. j)
      elseif dx * dx + dy * dy - open[j][6] > EPSILON then  --- If we're outside the circumcircle, skip this triangle
        --print('break________' .. j)
      else  --- Remove the triangle and add it's edges to the edge list
        table.insert(edges, {open[j][1], open[j][2]})
        table.insert(edges, {open[j][2], open[j][3]})
        table.insert(edges, {open[j][1], open[j][3]})

        --print('edges_________' .. j)
        --print('edges-------' .. open[j][1] .. '--------'.. open[j][2] .. '-----' .. open[j][3])

        table.remove(open, j)
      end
    end

--------------------------------------------
    for kk = #open, 1 ,-1  do
        --print('openData' .. open[kk][1] .. open[kk][2] .. open[kk][3])
    end

    for kk = #closed, 1 ,-1  do
        --print('closedData' .. closed[kk][1] .. closed[kk][2] .. closed[kk][3])
    end
-------------------------------------------------


    --- Remove any doubled edges
    self:dedup(edges)

    --- Add a new triangle for each edge
    for k = #edges, 1, -1 do
      local a = edges[k][1]
      local b = edges[k][2]
      table.insert(open, self:circumcircle(vertices, a, b, c))
      --print('circum---' .. a ..'---------'..b .. '----------' .. c)
    end

    for kk = #open, 1 ,-1  do
        --print('openData-----------' .. open[kk][1] .. open[kk][2] .. open[kk][3])
    end
  end

    --- Copy any remaining open triangles to the closed list, and then remove any triangles that share a vertex with the supertriangle, 
      --- building a list of triplets that represent triangles
    for t = #open, 1, -1 do
      table.insert(closed, open[t])
      -- print('open------closed----' .. t)
    end
    open = {}

    for i = #closed, 1, -1 do
      if closed[i][1] <= nVertices and closed[i][2] <= nVertices and closed[i][3] <= nVertices then
        table.insert(open, {closed[i][1], closed[i][2], closed[i][3]})

        -- print('open------' .. closed[i][1] .. '-------'.. closed[i][2] .. '--------'.. closed[i][3])
      end
    end

    return open
end

























