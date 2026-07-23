
# Guilloche rosette generator
# A guilloche pattern is created by overlapping epitrochoid curves
# parametric: x = (R+r)*cos(t) - d*cos((R+r)/r * t)
#             y = (R+r)*sin(t) - d*sin((R+r)/r * t)

defmodule Guilloche do
  def point(t, r1, r2, d) do
    x = (r1 + r2) * :math.cos(t) - d * :math.cos((r1 + r2) / r2 * t)
    y = (r1 + r2) * :math.sin(t) - d * :math.sin((r1 + r2) / r2 * t)
    {x, y}
  end

  def path(r1, r2, d, steps \\ 2000) do
    pts = for i <- 0..steps do
      t = i / steps * 2 * :math.pi * r2
      {x, y} = point(t, r1, r2, d)
      {x + 100, y + 100}
    end

    [{sx, sy} | rest] = pts
    coords = Enum.map(rest, fn {x, y} -> "L #{Float.round(x,2)} #{Float.round(y,2)}" end) |> Enum.join(" ")
    "M #{Float.round(sx,2)} #{Float.round(sy,2)} #{coords} Z"
  end
end

# Generate multiple rings of the rosette
# Outer large petal ring
p1 = Guilloche.path(70, 11, 75, 3000)
# Middle ring
p2 = Guilloche.path(50, 9, 54, 2800)
# Inner dense ring
p3 = Guilloche.path(32, 7, 35, 2400)
# Core ring
p4 = Guilloche.path(18, 5, 20, 2000)
# Innermost
p5 = Guilloche.path(8, 3, 9, 1600)

svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200" width="200" height="200">
  <path d="#{p1}" fill="none" stroke="#43b02a" stroke-width="0.2" opacity="0.5"/>
  <path d="#{p2}" fill="none" stroke="#43b02a" stroke-width="0.3" opacity="0.6"/>
  <path d="#{p3}" fill="none" stroke="#43b02a" stroke-width="0.4" opacity="0.7"/>
  <path d="#{p4}" fill="none" stroke="#2d8a1c" stroke-width="0.5" opacity="0.8"/>
  <path d="#{p5}" fill="none" stroke="#2d8a1c" stroke-width="0.6" opacity="0.9"/>
</svg>
"""

IO.puts(svg)
