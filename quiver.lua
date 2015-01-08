xx = torch.linspace(-3,3,10)
yy = torch.linspace(-3,3,10)
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
x1 = x0 + length * torch.cos(angle)
y1 = y0 + length * torch.sin(angle)

cm = {"#C7E9B4", "#7FCDBB", "#41B6C4", "#1D91C0", "#225EA8", "#0C2C84"}

ix = torch.floor(((length-length:min())/(length:max()-length:min())*5))
local colors = {}
for i=1,ix:size(1) do
   colors[i] = cm[ix[i]]
end

-- now we have x0, y0, x1, y1, color. Plot!
