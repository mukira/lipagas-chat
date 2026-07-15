defmodule QRTest do
  def run do
    data = "test qr vertical pills"
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

    # Group into vertical lines
    lines =
      for c <- 0..(size - 1) do
        col_data = for r <- 0..(size - 1), do: Enum.at(Enum.at(matrix_list, r), c)
        
        # Find contiguous 1s
        segments = Enum.reduce(Enum.with_index(col_data), [], fn {val, r}, acc ->
          if in_finder?.(r, c) or val == 0 do
            acc
          else
            case acc do
              [{start_r, end_r} | rest] when end_r == r - 1 -> [{start_r, r} | rest]
              _ -> [{r, r} | acc]
            end
          end
        end)
        
        for {start_r, end_r} <- segments do
          x = off + c * m + m / 2
          y1 = off + start_r * m + m / 2
          y2 = off + end_r * m + m / 2
          "<line x1='#{x}' y1='#{y1}' x2='#{x}' y2='#{y2}' stroke='#000000' stroke-width='#{m * 0.8}' stroke-linecap='round'/>"
        end
      end
      |> List.flatten()

    draw_teardrop = fn x, y, s, r, sharp_pos, color ->
      base = "<rect x='#{x}' y='#{y}' width='#{s}' height='#{s}' rx='#{r}' ry='#{r}' fill='#{color}'/>"
      sharp_box = case sharp_pos do
        :br -> "<rect x='#{x + s - r}' y='#{y + s - r}' width='#{r}' height='#{r}' fill='#{color}'/>"
        :bl -> "<rect x='#{x}' y='#{y + s - r}' width='#{r}' height='#{r}' fill='#{color}'/>"
        :tr -> "<rect x='#{x + s - r}' y='#{y}' width='#{r}' height='#{r}' fill='#{color}'/>"
        :tl -> "<rect x='#{x}' y='#{y}' width='#{r}' height='#{r}' fill='#{color}'/>"
      end
      base <> sharp_box
    end

    draw_finder = fn r_off, c_off ->
      x = off + c_off * m
      y = off + r_off * m
      sharp = case {r_off, c_off} do
        {0, 0} -> :br
        {0, _} -> :bl
        {_, 0} -> :tr
      end
      
      draw_teardrop.(x, y, 7*m, m*2, sharp, "#000000") <>
      draw_teardrop.(x+m, y+m, 5*m, m*1.5, sharp, "#ffffff") <>
      draw_teardrop.(x+2*m, y+2*m, 3*m, m*1.0, sharp, "#000000")
    end

    finders = [draw_finder.(0, 0), draw_finder.(0, size - 7), draw_finder.(size - 7, 0)] |> Enum.join()

    cx = dim / 2
    cy = dim / 2
    lr = m * 3.8

    center =
      "<circle cx='#{cx}' cy='#{cy}' r='#{lr + m}' fill='#ffffff'/>" <>
      "<circle cx='#{cx}' cy='#{cy}' r='#{lr}' fill='#43b02a'/>"

    IO.puts("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 #{dim} #{dim}' width='80' height='80' style='background:white;border-radius:4px;'>#{finders}#{Enum.join(lines)}#{center}</svg>")
  end
end

QRTest.run()
