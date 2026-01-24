extends TileMapLayer

@export var width: int = 80
@export var height: int = 50
@export var fill_percent: int = 45 
@export var iterations: int = 5
@export var border_size: int = 4 # How thick the water border starts

# Tile Settings (Source ID 1)
const SOURCE_ID = 1
const GRASS_TILES = [Vector2i(0,0), Vector2i(1,0), Vector2i(2,0), Vector2i(3,0)]
const DIRT_TILES  = [Vector2i(4,0), Vector2i(5,0)]
const ROCK_TILES  = [Vector2i(6,0), Vector2i(7,0)]
const WATER_TILES = [Vector2i(18,0), Vector2i(19,0)]

var map_data = {} # 0: Grass, 1: Rock/Dirt, 2: Water

func _ready():
	randomize()
	generate_level()

func generate_level():
	map_data.clear()
	
	# 1. Initial Setup
	for x in range(width):
		for y in range(height):
			var pos = Vector2i(x, y)
			
			# Force a water border at the very edges
			if x < border_size or x >= width - border_size or y < border_size or y >= height - border_size:
				map_data[pos] = 2 
			else:
				# Randomly seed the inner area
				map_data[pos] = 1 if randi() % 100 < fill_percent else 0
	
	# 2. Smoothing (Soften the edges)
	for i in range(iterations):
		smooth_map()
	
	# 3. Draw
	draw_map()

func smooth_map():
	var new_map = map_data.duplicate()
	for x in range(1, width - 1):
		for y in range(1, height - 1):
			var pos = Vector2i(x, y)
			var neighbors = get_neighbor_counts(x, y)
			
			# If surrounded by water, become water
			if neighbors.water > 4:
				new_map[pos] = 2
			# Standard Cave Logic for Rock/Dirt
			elif neighbors.wall > 4:
				new_map[pos] = 1
			elif neighbors.wall < 4:
				new_map[pos] = 0
				
	map_data = new_map

# Helper to count different types of neighbors
func get_neighbor_counts(grid_x, grid_y):
	var counts = {"wall": 0, "water": 0}
	for x in range(grid_x - 1, grid_x + 2):
		for y in range(grid_y - 1, grid_y + 2):
			if x == grid_x and y == grid_y: continue
			var val = map_data.get(Vector2i(x, y), 2) # Default to water if out of bounds
			if val == 1: counts.wall += 1
			if val == 2: counts.water += 1
	return counts

func draw_map():
	clear()
	for x in range(width):
		for y in range(height):
			var pos = Vector2i(x, y)
			var type = map_data[pos]
			var tile: Vector2i
			
			match type:
				2: # Water
					tile = WATER_TILES.pick_random()
				1: # Rock/Dirt
					var wall_count = get_neighbor_counts(x, y).wall
					tile = ROCK_TILES.pick_random() if wall_count == 8 else DIRT_TILES.pick_random()
				0: # Grass
					tile = GRASS_TILES.pick_random()
			
			set_cell(pos, SOURCE_ID, tile)
