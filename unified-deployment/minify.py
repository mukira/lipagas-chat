import re
import sys

def minify_css(css):
    css = re.sub(r'/\*.*?\*/', '', css, flags=re.DOTALL)
    css = re.sub(r'\s+', ' ', css)
    css = re.sub(r'\s*([\{\}:;,])\s*', r'\1', css)
    return css.strip()

def minify_js(js):
    js = re.sub(r'//.*', '', js)
    js = re.sub(r'/\*.*?\*/', '', js, flags=re.DOTALL)
    js = re.sub(r'\s+', ' ', js)
    js = re.sub(r'\s*([\{\}\(\)\[\]=;:,\.\+\-\*/<>!&\|])\s*', r'\1', js)
    js = re.sub(r'\bvar\s+', 'var ', js)
    js = re.sub(r'\bfunction\s+', 'function ', js)
    js = re.sub(r'\breturn\s+', 'return ', js)
    js = re.sub(r'\bnew\s+', 'new ', js)
    return js.strip()

with open('nginx/html/planna-theme.css', 'r') as f:
    css = f.read()
with open('nginx/html/planna-theme.css', 'w') as f:
    f.write(minify_css(css))

with open('nginx/html/planna-testimonials.js', 'r') as f:
    js = f.read()
with open('nginx/html/planna-testimonials.js', 'w') as f:
    f.write(minify_js(js))
