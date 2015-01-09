-- quiver plots
xx = torch.linspace(-3,3,100)
yy = torch.linspace(-3,3,100)
local function meshgrid(x,y)
   local xx = torch.repeatTensor(x, y:size(1),1)
   local yy = torch.repeatTensor(y:view(-1,1), 1, x:size(1))
   return xx, yy
end
Y, X = meshgrid(xx, yy)
U = -torch.pow(X,2) + Y -1
V =  X - torch.pow(Y,2) +1
speed = torch.sqrt(torch.cmul(U,U) + torch.cmul(V,V))
theta = torch.atan(torch.cdiv(V,U))

-- line start
x0 = X:view(-1)
y0 = Y:view(-1)

-- line length and angle
length = speed:view(-1)/40
angle = theta:view(-1)

-- line end
x1 = x0 + torch.cmul(length, torch.cos(angle))
y1 = y0 + torch.cmul(length, torch.sin(angle))
----------------------------------------------------
-- calculate arrow-head
local ll = (x1 - x0)
local ll2 = (y1 - y0)
local len = torch.sqrt(torch.cmul(ll,ll) + torch.cmul(ll2,ll2))
h = len / 10
w = len / 100
Ux = torch.cdiv(ll,len)
Uy = torch.cdiv(ll2,len)
Vx = -Uy
Vy = Ux
v1x = x1 - torch.cmul(Ux,h) + torch.cmul(Vx,w);
v1y = y1 - torch.cmul(Uy,h) + torch.cmul(Vy,w);

v2x = x1 - torch.cmul(Ux,h) - torch.cmul(Vx,w);
v2y = y1 - torch.cmul(Uy,h) - torch.cmul(Vy,w);
----------------------------
cm = {"#C7E9B4", "#7FCDBB", "#41B6C4", "#1D91C0", "#225EA8", "#0C2C84"}

ix = torch.floor(((length-length:min())/(length:max()-length:min())*5))
local colors = {}
for i=1,ix:size(1) do
   colors[i] = cm[ix[i]]
end
plot = Plot():segment(x0, y0, x1,y1, colors,'example'):segment(v1x,v1y,v2x,v2y,colors):segment(v1x,v1y,x1,y1,colors):segment(v2x,v2y,x1,y1,colors):draw()
