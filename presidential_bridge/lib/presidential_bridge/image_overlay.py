import sys
import urllib.request
from PIL import Image, ImageDraw, ImageFont
import os
import os

def download_font(url, path):
    if not os.path.exists(path):
        urllib.request.urlretrieve(url, path)
    return path

def composite_image(image_url, headline, subtitle, output_path, logo_path):
    # 1. Download original image
    # Fetch highest quality if it's a Twitter image
    if 'pbs.twimg.com' in image_url and '?format=' not in image_url:
        image_url = f"{image_url}?name=orig"
        
    req = urllib.request.Request(image_url, headers={
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    })
    temp_input_path = output_path.replace("overlay_v11_", "temp_input_")
    try:
        with urllib.request.urlopen(req) as response:
            with open(temp_input_path, "wb") as f:
                f.write(response.read())
    except Exception as e:
        print(f"Failed to download image: {e}", file=sys.stderr)
        sys.exit(1)

    # Open the image
    img = Image.open(temp_input_path).convert("RGBA")
    
    # 2. Force exactly 1080x1080 via center crop
    target_width = 1080
    target_height = 1080
    
    # Calculate crop dimensions to get a perfect square from the center
    orig_w, orig_h = img.size
    min_dim = min(orig_w, orig_h)
    
    left = (orig_w - min_dim) / 2
    top = (orig_h - min_dim) / 2
    right = (orig_w + min_dim) / 2
    bottom = (orig_h + min_dim) / 2
    
    # Crop to square, then resize to 1080x1080
    img = img.crop((left, top, right, bottom))
    img = img.resize((target_width, target_height), Image.Resampling.LANCZOS)
    
    # Create drawing context
    draw = ImageDraw.Draw(img)
    
    # 3. Add Logo (Top Right)
    try:
        logo = Image.open(logo_path).convert("RGBA")
        
        # Resize logo to be 180px wide for a sleeker, subtle look
        logo_w = 180
        l_pct = (logo_w / float(logo.size[0]))
        logo_h = int((float(logo.size[1]) * float(l_pct)))
        logo = logo.resize((logo_w, logo_h), Image.Resampling.LANCZOS)
        
        # Paste at top right with 40px padding
        padding = 40
        pos = (target_width - logo_w - padding, padding)
        img.paste(logo, pos, logo)
    except Exception as e:
        print(f"Warning: Could not add logo: {e}", file=sys.stderr)

    # 5. Draw Text with 10% Padding
    font_bold_path = download_font("https://github.com/googlefonts/roboto/raw/main/src/hinted/Roboto-Bold.ttf", "/tmp/Roboto-Bold.ttf")
    font_reg_path = download_font("https://github.com/googlefonts/roboto/raw/main/src/hinted/Roboto-Regular.ttf", "/tmp/Roboto-Regular.ttf")
    
    font_bold = ImageFont.truetype(font_bold_path, 60)
    font_reg = ImageFont.truetype(font_reg_path, 36)
    
    # 10% padding left and right -> 80% available width
    text_x = int(target_width * 0.1)
    max_text_width = int(target_width * 0.8)
    
    # Wrap subtitle function
    def wrap_text(text, font, max_width):
        lines = []
        words = text.split(' ')
        current_line = ""
        for word in words:
            test_line = current_line + word + " "
            # Use getbbox to get width in Pillow 10+
            bbox = font.getbbox(test_line)
            width = bbox[2] - bbox[0]
            if width <= max_width:
                current_line = test_line
            else:
                lines.append(current_line.strip())
                current_line = word + " "
        if current_line:
            lines.append(current_line.strip())
        return lines

    import html
    headline = html.unescape(headline)
    subtitle = html.unescape(subtitle)

    headline_lines = wrap_text(headline, font_bold, max_text_width)
    subtitle_lines = wrap_text(subtitle, font_reg, max_text_width)
    
    # 4. Draw Full-Height Gradient (Black at bottom fading to transparent at top)
    gradient = Image.new('L', (1, target_height))
    for y in range(target_height):
        alpha = int(255 * (y / target_height))
        gradient.putpixel((0, y), alpha)
    gradient = gradient.resize((target_width, target_height))
    
    # Base color is pure black
    overlay_black = Image.new('RGBA', (target_width, target_height), (0, 0, 0, 255))
    img.paste(overlay_black, (0, 0), gradient)
    
    # Calculate base layout so text fits with exactly 10% padding from the bottom edge
    bottom_padding = int(target_height * 0.1)
    headline_height = len(headline_lines) * 72
    subtitle_height = len(subtitle_lines) * 46 if len(subtitle_lines) > 0 else 0
    total_text_height = headline_height + subtitle_height
        
    start_y = target_height - bottom_padding - total_text_height
    
    # Headline
    current_y = start_y
    for line in headline_lines:
        draw.text((text_x, current_y), line, font=font_bold, fill=(255, 255, 255, 255))
        current_y += 72
    
    # Subtitle
    if len(subtitle_lines) > 0:
        for line in subtitle_lines:
            draw.text((text_x, current_y), line, font=font_reg, fill=(200, 200, 200, 255))
            current_y += 46

    # Save output temporarily
    final_img = img.convert("RGB") # Drop alpha before saving as JPEG
    final_img.save(output_path, "JPEG", quality=85)
    
    # 6. Upload to Cloudflare R2
    import boto3
    
    # Get credentials from environment
    endpoint_url = os.environ.get('R2_ENDPOINT_URL', 'https://03dcccad58bf52aab121c1af49645bc9.r2.cloudflarestorage.com')
    access_key = os.environ.get('R2_ACCESS_KEY_ID', 'd52b89c4d53fdd4d15b5a0f708ac4f0e')
    secret_key = os.environ.get('R2_SECRET_ACCESS_KEY', 'a0b07ed1590341393b46b8a1c4a65a662af6bae208a77ca51134e2f9bc071155')
    bucket = os.environ.get('R2_BUCKET_NAME', 'presidential-bot')
    public_url_base = os.environ.get('R2_PUBLIC_URL_BASE', 'https://pub-649993d9eee74362a33a90ae2e2d8939.r2.dev')
    
    s3 = boto3.client('s3',
        endpoint_url = endpoint_url,
        aws_access_key_id = access_key,
        aws_secret_access_key = secret_key,
        region_name = 'auto'
    )
    
    object_name = os.path.basename(output_path)
    s3.upload_file(output_path, bucket, object_name, ExtraArgs={'ContentType': 'image/jpeg'})
    
    # Return the public URL
    public_url = f"{public_url_base}/{object_name}"
    print(public_url)
    
    # Cleanup
    try:
        os.remove(output_path)
        os.remove(output_path.replace("overlay_v11_", "temp_input_"))
    except:
        pass

if __name__ == "__main__":
    if len(sys.argv) < 6:
        print("Usage: python image_overlay.py <image_url> <headline> <subtitle> <output_path> <logo_path>")
        sys.exit(1)
    
    composite_image(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
