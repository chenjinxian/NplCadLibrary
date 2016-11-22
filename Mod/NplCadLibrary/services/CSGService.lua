--[[
Title: CSGService 
Author(s): leio
Date: 2016/8/23
Desc: 
use the lib:
------------------------------------------------------------
NPL.load("(gl)Mod/NplCadLibrary/services/CSGService.lua");
local CSGService = commonlib.gettable("Mod.NplCadLibrary.services.CSGService");
local output = CSGService.buildPageContent("cube();")
commonlib.echo(output);
------------------------------------------------------------
]]
NPL.load("(gl)Mod/NplCadLibrary/csg/CSGVector.lua");
NPL.load("(gl)script/ide/math/Matrix4.lua");
NPL.load("(gl)script/ide/math/math3d.lua");
NPL.load("(gl)Mod/NplCadLibrary/services/NplCadEnvironment.lua");
local Matrix4 = commonlib.gettable("mathlib.Matrix4");
local CSGVector = commonlib.gettable("Mod.NplCadLibrary.csg.CSGVector");
local CSGService = commonlib.gettable("Mod.NplCadLibrary.services.CSGService");
local math3d = commonlib.gettable("mathlib.math3d");
local NplCadEnvironment = commonlib.gettable("Mod.NplCadLibrary.services.NplCadEnvironment");
CSGService.default_color = {1,1,1};
function CSGService.setColor(csg_node,color)
	if(not csg_node or  not csg_node.polygons)then return end
	color = color or {};
	color[1] = color[1] or 1;
	color[2] = color[2] or 1;
	color[3] = color[3] or 1;
	for k,v in ipairs(csg_node.polygons) do
		v.shared = v.shared or {};
		v.shared.color = color;
	end
end

local white = {1,1,1};

function CSGService.toMesh(csg_node)
	if(not csg_node)then return end
	local vertices = {};
	local indices = {};
	local normals = {};
	local colors = {};
	
	for __,polygon in ipairs(csg_node.polygons) do
		local start_index = #vertices+1;
		local normal = polygon:GetPlane().normal;
		for __,vertex in ipairs(polygon.vertices) do
			vertices[#vertices+1] = {vertex.pos[1],vertex.pos[2],vertex.pos[3]};
			normals[#normals+1] = {normal[1],normal[2],normal[3]} 
			local shared = polygon.shared or {};
			local color = shared.color or white;
			colors[#colors+1] = color;
		end
		local size = #(polygon.vertices) - 1;
		for i = 2,size do
			indices[#indices+1] = start_index;
			indices[#indices+1] = start_index + i-1;
			indices[#indices+1] = start_index + i;
		end
	end
	return vertices,indices,normals,colors;
end

local pos = {};
function CSGService.applyMatrix(csg_node,matrix)
	if(not matrix or not csg_node)then return end

	for __,polygon in ipairs(csg_node.polygons) do
		for __,vertex in ipairs(polygon.vertices) do
			pos[1], pos[2], pos[3] = vertex.pos[1],vertex.pos[2],vertex.pos[3];
			math3d.VectorMultiplyMatrix(pos, pos, matrix);
			vertex.pos[1] = pos[1];
			vertex.pos[2] = pos[2];
			vertex.pos[3] = pos[3];

			--local normal = {vertex.normal[1],vertex.normal[2],vertex.normal[3]};
			--normal = math3d.VectorMultiplyMatrix(nil, normal, matrix);
			--vertex.normal[1] = normal[1];
			--vertex.normal[2] = normal[2];
			--vertex.normal[3] = normal[3];
		end
		polygon.plane = nil;
	end
end
function CSGService.operateTwoNodes(pre_csg_node,cur_csg_node,csg_action)
	local bResult = false;
	if(pre_csg_node and cur_csg_node)then
		if(csg_action == "union")then
			cur_csg_node = pre_csg_node:union(cur_csg_node);
			bResult = true;
		elseif(csg_action == "difference")then
			cur_csg_node = pre_csg_node:subtract(cur_csg_node);
			bResult = true;
		elseif(csg_action == "intersection")then
			cur_csg_node = pre_csg_node:intersect(cur_csg_node);
			bResult = true;
		else
			-- Default action is "union".
			--cur_csg_node = pre_csg_node:union(cur_csg_node);
		end
	end
	return cur_csg_node,bResult;
end

-- find tag value in all of its parent recursively
-- @return tagValue, sceneNode: if no tagValue is found, the sceneNode is the rootNode.
function CSGService.findTagValue(node,name)
	if(not node)then
		return
	end
	local p = node;
	local lastNode;
	while(p) do
		local v = p:getTag(name);
		if(v)then
			return v,p;
		end
		lastNode = p;
		p = p:getParent();
	end
	return nil, lastNode;
end

function CSGService.equalsColor(color_1,color_2)
	if(color_1 and color_2)then
		return (color_1[1] == color_2[1] and color_1[2] == color_2[2] and color_1[3] == color_2[3]);
	end
end
--[[
	return {
		successful = successful,
		csg_node_values = csg_node_values,
		compile_error = compile_error,
	}
--]]
function CSGService.buildPageContent(code)
	code = CSGService.appendLoadXmlFunction(code)
	if(not code or code == "") then
		return;
	end
	local output = {}
	local code_func, errormsg = loadstring(code);
	if(code_func) then
		local env = NplCadEnvironment:new();
		setfenv(code_func, env);
		local ok, result = pcall(code_func);
		if(ok) then
			if(type(env.main) == "function") then
				setfenv(env.main, env);
				ok, result = pcall(env.main);
			end
		end
		CSGService.scene = env.scene;
		local render_list = CSGService.getRenderList(env.scene)
		output.successful = ok;
		output.csg_node_values = render_list;
		output.compile_error = result;
	else
		output.successful = false;
		output.compile_error =  errormsg;
	end
	return output;
end
function CSGService.appendLoadXmlFunction(code)
	if(code)then
		local first_line;
		for line in string.gmatch(code,"[^\r\n]+") do
			first_line = line;
			break;
		end
		if(first_line)then
			if(string.find(first_line,"nplcad"))then
				code = string.format("loadXml([[%s]])",code);
				return code;
			end
		end
		return code;
	end
end

function CSGService.getRenderList(scene)
	if(not scene)then
		return
	end
	local fromTime = ParaGlobal.timeGetTime();
	LOG.std(nil, "info", "CSG", "\n------------------------------\nbegin render scene\n");

	local function BeforeChildVisit_(node)
		local csg_node = CSGService.getTransformedCSGNode(node);
		if(csg_node)then
			local actionName, actionNode = CSGService.findTagValue(node,"csg_action");
			actionNode:pushActionParam(csg_node);
			LOG.std(nil, "info", "CSG", "begin csg_node with %d polygons", csg_node:GetPolygonCount());
		else
			LOG.std(nil, "info", "CSG", "begin node with (%s) tag", node:getTag("csg_action") or "empty");
		end
	end

	local function AfterChildVisit_(node)
		local action_params = node:popAllActionParams();
		if(action_params) then
			local actionName = node:getTag("csg_action");
			local fromTime = ParaGlobal.timeGetTime();
			local result_csg_node = CSGService.doCSGNodeAction(actionName, action_params);
			LOG.std(nil, "info", "CSG", "csg_node action (%s: with %d nodes) finished in %.3f seconds with %d polygons", 
				actionName or "none", action_params and #action_params or 0, 
				(ParaGlobal.timeGetTime()-fromTime)/1000, result_csg_node and result_csg_node:GetPolygonCount() or 0);
			local actionName, actionNode = CSGService.findTagValue(node:getParent() or scene,"csg_action");
			if(actionNode ~= node) then
				actionNode:pushActionParam(result_csg_node);
			end
		end
	end

	scene:visit(BeforeChildVisit_, AfterChildVisit_);

	-- convert all resulting csg_nodes to meshes
	local render_list = {};

	local result = scene:popAllActionParams();
	if(result) then
		for i = 1, #result do
			local vertices,indices,normals,colors = CSGService.toMesh(result[i]);
			table.insert(render_list,{
				vertices = vertices,
				indices = indices,
				normals = normals,
				colors = colors,
			});
		end
	end
	LOG.std(nil, "info", "CSG", "\n\nfinished render scene in %.3f seconds\n------------------------------", (ParaGlobal.timeGetTime()-fromTime)/1000);
	return render_list;
end

-- @param csg_action: name of the operation. 
-- @param csg_nodes: array of csg node operands
-- @return csgNode, bSucceed:  csgNode is the result.
function CSGService.doCSGNodeAction(csg_action, csg_nodes)
	local len = #csg_nodes;
	if(len == 0)then
		return;
	end
	local first_node = csg_nodes[1];
	local result_node = first_node;
	local bSucceed = true;
	for i=2, len do
		result_node, bSucceed = CSGService.operateTwoNodes(result_node, csg_nodes[i], csg_action);
		if(not bSucceed) then
			break;
		end
	end
	return result_node, bSucceed;
end

function CSGService.findCsgNode(node)
		if(not node)then return end
		local drawable = node:getDrawable();
		if(drawable and drawable.getCSGNode)then
			local cur_csg_node = drawable:getCSGNode();
			return cur_csg_node;
		end
end
function CSGService.visitNode(node,input_params)
	if(not node)then return end
	local nodes_map = input_params.nodes_map;
	if(nodes_map[node]["csg_node"])then
		return
	end
	local child = node:getFirstChild();
	local top_csg_action = CSGService.findTagValue(node,"csg_action");
	local temp_list = {};
	while(child) do
		local csg_node = nodes_map[child]["csg_node"];
		if(csg_node)then
			if(top_csg_action)then
				table.insert(temp_list,{
					csg_node = csg_node,
				});	
			else
				table.insert(input_params.result,{
					csg_node = csg_node,
				});	
			end
			
		end
		nodes_map[child]["csg_node"] = nil;
		child = child:getNextSibling();
	end	
	local csg_node = CSGService.doCSGOperation(top_csg_action, temp_list);
	nodes_map[node]["csg_node"] = csg_node;
end

-- @param node: a scene node
-- @return csg_node, if scene node is a csg node and world transformation is applied to it. 
function CSGService.getTransformedCSGNode(node)
	local csg_node = CSGService.findCsgNode(node);
	if(csg_node)then
		csg_node = csg_node:clone();-- clone a new node for operation. 
		local color = CSGService.findTagValue(node,"color");
		if(color)then
			if(not CSGService.equalsColor(color,CSGService.default_color))then
				CSGService.setColor(csg_node,color);
			end
		end
		local world_matrix = node:getWorldMatrix();
		CSGService.applyMatrix(csg_node,world_matrix);
		return csg_node;
	end
end
-- Read csg code from a file.
function CSGService.readFile(filepath)
	if(not filepath)then return end
	local file = ParaIO.open(filepath, "r");
	if(file:IsValid()) then
		local text = file:GetText();
		file:close();
		return text;
	end
end
function CSGService.saveFile(filepath,content)
	if(filepath and content)then
		ParaIO.CreateDirectory(filepath);
		local file = ParaIO.open(filepath, "w");
		if(file:IsValid()) then
			file:WriteString(content);
			file:close();

			return true;
		end
	end
end
