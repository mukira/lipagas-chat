defmodule QRTest do
  def run do
    data = "test qr blob style"
    encoded = EQRCode.encode(data, :h)
    %EQRCode.Matrix{matrix: rows} = encoded
    size = EQRCode.Matrix.size(encoded)
    m = 10
    q = 4
    dim = (size + 2 * q) * m
    off = q * m

    matrix_list = rows |> Tuple.to_list() |> Enum.map(&Tuple.to_list/1)

    in_finder? = fn r, c ->
      (r <= 6 and c <= 6) or (r <= 6 and c >= size - 7) or (r >= size - 7 and c <= 6)
    end

    get_val = fn r, c ->
      if r >= 0 and r < size and c >= 0 and c < size do
        Enum.at(Enum.at(matrix_list, r), c) == 1
      else
        false
      end
    end

    # Blob modules
    modules =
      for r <- 0..(size - 1), c <- 0..(size - 1), get_val.(r, c), not in_finder?.(r, c) do
        cx = off + c * m + m / 2
        cy = off + r * m + m / 2
        
        # Base circle
        base = "<circle cx='#{cx}' cy='#{cy}' r='#{m * 0.45}' fill='#000000'/>"
        
        # Right bridge
        right_bridge =
          if get_val.(r, c + 1) and not in_finder?.(r, c + 1) do
            "<rect x='#{cx}' y='#{cy - m * 0.45}' width='#{m}' height='#{m * 0.9}' fill='#000000'/>"
          else
            ""
          end
          
        # Bottom bridge
        bottom_bridge =
          if get_val.(r + 1, c) and not in_finder?.(r + 1, c) do
            "<rect x='#{cx - m * 0.45}' y='#{cy}' width='#{m * 0.9}' height='#{m}' fill='#000000'/>"
          else
            ""
          end
          
        base <> right_bridge <> bottom_bridge
      end
      |> Enum.join()

    # Finders
    draw_finder = fn r_off, c_off ->
      x = off + c_off * m
      y = off + r_off * m
      
      # Outer ring
      outer = "<rect x='#{x}' y='#{y}' width='#{7*m}' height='#{7*m}' rx='#{1.5*m}' ry='#{1.5*m}' fill='#000000'/>"
      # Inner white gap
      white = "<rect x='#{x+m}' y='#{y+m}' width='#{5*m}' height='#{5*m}' rx='#{1.0*m}' ry='#{1.0*m}' fill='#ffffff'/>"
      # Inner pupil (circle)
      pupil = "<circle cx='#{x + 3.5*m}' cy='#{y + 3.5*m}' r='#{1.5*m}' fill='#000000'/>"
      
      outer <> white <> pupil
    end

    finders = [draw_finder.(0, 0), draw_finder.(0, size - 7), draw_finder.(size - 7, 0)] |> Enum.join()

    # Center Logo
    cx = dim / 2
    cy = dim / 2
    lr = m * 5  # increased radius for more prominent logo

    center =
      "<circle cx='#{cx}' cy='#{cy}' r='#{lr + m}' fill='#ffffff'/>" <>
      "<circle cx='#{cx}' cy='#{cy}' r='#{lr}' fill='#43b02a'/>"

    IO.puts("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 #{dim} #{dim}' width='100%' height='100%' style='background:white;border-radius:4px;'>#{finders}#{modules}#{center}</svg>")
  end
end

QRTest.run()
