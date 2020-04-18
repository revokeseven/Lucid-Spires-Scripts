module Cache
  def self.grid(filename)
    load_bitmap("Graphics/Grid/", filename)
  end
end

module Sound
  def self.play_grid_error
    RPG::SE.new("FEA - Error1", 60, 95).play
  end
  def self.play_grid_move
    RPG::SE.new("FEA - Pop2", 80, 90).play
  end
end

module Revoked
  module Grid

    RadiusY = 1
    RadiusX = 4
    MaxHeight = 1 + 2 * RadiusY
    MaxWidth  = 1 + 2 * RadiusX

    TileHeight = 50
    TileWidth  = 58

    TileXOffset = -3
    TileYOffset = -10

    UnitXOffset = 32
    UnitYOffset = 48

    DefaultPositions = {
      1 => [0,1], # Clement
      2 => [1,2], # Amaina
      3 => [1,1], # Vermund
      4 => [-1,3] # Rinore
    }

    #--------------------------------------------------------------------------
    # ■ Get array of spaces based on an item's grid tags and any battler mods.
    #==========================================================================
    def self.position(row, col)
      result = {}

      w = TileWidth
      h = TileHeight
      base_x = Graphics.width / 2
      base_y = Graphics.height / 2
      x_offset = TileXOffset - (0.5 * w).to_i
      y_offset = TileYOffset - (0.5 * h).to_i
      result[:x] = base_x + x_offset + ((col + 0.5 * row) * w).to_i
      result[:y] = base_y + y_offset + row * h

      return result
    end

    def self.coordinates_from_pos(x_pos, y_pos)
      max_row = Revoked::Grid::RadiusY
      max_col = Revoked::Grid::RadiusX
      w = TileWidth
      base_x = Graphics.width / 2
      x_offset = TileXOffset - (0.5 * w).to_i

      row_split = Graphics.height / (2 * max_row + 1)
      row = y_pos / row_split - max_row
      col = (((x_pos - base_x - x_offset).to_i / w) - 0.5 * row).to_i

      return [row,col]
    end

    # Return the min and max x (column) value on a given row.
    def self.column_boundary(row)
      base = Revoked::Grid::RadiusX
      min = -base - (row < 0 ? row : 0)
      max = base - (row > 0 ? row : 0)
      return {:min => min, :max => max}
    end

    def self.distance_between_tile(dest, orig)
      return distance_between_rc(dest.coordinates_rc, orig.coordinates_rc)
    end

    def self.distance_between_rc(dest, orig)
      return [dest[1] - orig[1], dest[0] - orig[0]].max
    end

  #----------------------------------------------------------------------------
  # Area building methods (Returns coordinates).
  #============================================================================
    # get the indices of all nearby tiles with a given radius. [y, x]
    def self.calc_radius(tile_index = [0,0], radius = 1)
      offset_x = tile_index[1]
      offset_y = tile_index[0]
      radius_x = radius
      radius_y = radius

      result = []

      (-radius_y..radius_y).each do |row|
        left_ind  = row < 0 ? -radius_x - row : -radius_x
        right_ind = row > 0 ? radius_x - row : radius_x

        (left_ind..right_ind).each do |col|
          result.push([row + offset_y, col + offset_x])
        end
      end
      return result
    end

    # get indices of a tile and adjacent ones in a curve based on direction.
    def self.calc_arc(origin_rc, direction, range = 1)
      # direction can be :left or :right.
      offset_x = origin_rc[1]
      offset_y = origin_rc[0]

      result = []

      dir = :right ? 1 : -1
      if direction == :right
        range.times do |i|
          result.push([(-1) + offset_y, (i + 1) * dir + offset_x])
          result.push([offset_y, (i + 1) * dir + offset_x])
          result.push([(1) + offset_y, (i) * dir + offset_x])
        end
      elsif direction == :left
        range.times do |i|
          result.push([(-1) + offset_y, (-i) * dir + offset_x])
          result.push([offset_y, (-i - 1) * dir + offset_x])
          result.push([(1) + offset_y, (-i - 1) * dir + offset_x])
        end
      end
      return result

    end

    # get array of spaces based on an item's grid tags and any battler mods.
    def self.make_interact_tiles(grid, origin, item)
      range = item.ability_range

      # Array of tiles.
      selectable = []
      selection_tags = item.grid_selectable_tags
      dir = dir_from_tags(selection_tags)

      selection_tags.each do |tag|
        case tag
        when :self
          selectable << origin
        when :radius
          selectable += grid.tiles_from_coordinates(calc_radius(origin, range))
        when :arc
          selectable += grid.tiles_from_coordinates(calc_arc(origin, dir, range))
        end
      end

      selectable.uniq!
      return {:available => selectable, :potential => []}
    end

    def self.make_area_tiles(grid, offset_t, item)
      offset_rc = offset_t.coordinates_rc
      area = []
      area_tags = item.grid_area_tags
      dir = dir_from_tags(area_tags)

      area_tags.each do |tag|
        case tag
        when :single
          area << offset_t
        when :arc
          area += grid.tiles_from_coordinates(calc_arc(offset_rc, dir, range))
        else
          area << offset_t
        end
      end

      area.uniq!
      return area
    end

    def self.auto_cursor(grid, origin, selectable, item)
      anchor_coordinates = []
      target_type = item.grid_target_type

      can_target_self = item.grid_selectable_tags.include?(:not_self)

      if target_type == :self || !selectable || selectable.empty?
        return grid.get(*origin)
      end

      targets_in_range = unit_distances_in_area(grid, selectable, origin)
      return selectable[0] if targets_in_range.empty?

      if target_type == :enemy
        targets_in_range.reject {|tuple| !tuple[0].enemy?}
      elsif target_type == :ally && !can_target_self
        targets_in_range.reject {|tuple| !tuple[0].actor?}
      elsif target_type == :ally_dead
        targets_in_range.reject {|tuple| !tuple[0].actor? && !tuple[0].dead?}
      end

      return selectable[0] if targets_in_range.empty?

      anchor_coordinates = targets_in_range[0][1][1]
      return anchor_coordinates
    end

    # return an array of battlers in the given region.
    def self.units_in_area(grid, tiles)
      units = tiles.collect {|tile| tile.unit_contents }.compact.uniq
      return units
    end

    # return an array of enemy, distance, tile trios.
    def self.unit_distances_in_area(grid, tiles, origin)
      units = {}
      tiles.each do |tile|
        battlers = tile.unit_contents
        battlers.each do |b|
          dist = distance_between_tile(tile, grid.get(*origin))
          units[b] = !units[b] ? [dist, tile] : [[dist, units[b][0]].min, tile]
        end
      end
      p(units.to_a)
      return units.to_a.sort_by {|_,dist| dist }
    end

    #--------------------------------------------------------------------------
    # ■ Grid battler location calculations.
    #==========================================================================
    def self.set_grid_location(unit)

    end

    #--------------------------------------------------------------------------
    # ■ Grid mini helper methods.
    #==========================================================================
    def self.dir_from_tags(tags)
      tags.each do |tag|
        case tag
        when :left ; return :left
        when :right ; return :right
        when :top_left ; return :top_left
        when :top_right ; return :top_right
        when :btm_left ; return :btm_left
        when :btm_right ; return :btm_right
        else
          return :left
        end
      end
    end

  end # Grid module
end
