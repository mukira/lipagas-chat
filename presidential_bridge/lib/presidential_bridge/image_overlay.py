import sys
import urllib.request
import ssl
from PIL import Image, ImageDraw, ImageFont
import os

def download_font(url, path):
    if not os.path.exists(path):
        ctx = ssl._create_unverified_context()
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, context=ctx) as resp, open(path, 'wb') as f:
            f.write(resp.read())
    return path

def download_and_open_image(image_url, temp_input_path):
    fallback_urls = [
        "/app/lib/presidential_bridge/ruto_fallback.jpg"
    ]
    urls_to_try = [image_url] + fallback_urls
    
    if image_url and 'pbs.twimg.com' in image_url and '?format=' not in image_url:
        urls_to_try.insert(0, f"{image_url}?name=orig")

    ssl_ctx = ssl._create_unverified_context()

    for url in urls_to_try:
        if not url:
            continue
        try:
            if os.path.exists(url):
                with open(url, "rb") as f:
                    with open(temp_input_path, "wb") as tf:
                        tf.write(f.read())
                img = Image.open(temp_input_path).convert("RGBA")
                return img

            req = urllib.request.Request(url, headers={
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
            })
            with urllib.request.urlopen(req, timeout=10, context=ssl_ctx) as response:
                if response.status == 200:
                    with open(temp_input_path, "wb") as f:
                        f.write(response.read())
                    img = Image.open(temp_input_path).convert("RGBA")
                    if min(img.size) < 300:
                        print(f"Warning: Image from {url} is too low resolution ({img.size}). Skipping.", file=sys.stderr)
                        continue
                    return img
        except Exception as e:
            print(f"Warning: Failed to fetch image from {url}: {e}", file=sys.stderr)
            continue
            
    # Final fallback: local high-res working presidential fallback image URL if all HTTP fetches failed
    local_fallback_path = "/app/lib/presidential_bridge/ruto_fallback.jpg"
    try:
        if os.path.exists(local_fallback_path):
            with open(local_fallback_path, "rb") as f:
                with open(temp_input_path, "wb") as tf:
                    tf.write(f.read())
            return Image.open(temp_input_path).convert("RGBA")
    except Exception as e:
        print(f"Warning: Failed to load local fallback image: {e}", file=sys.stderr)

    # Emergency fallback: neutral slate background instead of pure black
    return Image.new("RGBA", (1080, 1080), (70, 80, 95, 255))

def composite_image(image_url, headline, subtitle, output_path, logo_path):
    temp_input_path = output_path + ".input.tmp"
    img = download_and_open_image(image_url, temp_input_path)
    
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
    
    import html
    import re

    headline = html.unescape(headline).strip()
    subtitle = html.unescape(subtitle).strip()

    # Automated Grammar Engine: Article & Preposition Repair
    def fix_missing_articles(text):
        text = re.sub(r'\bI Bid Farewell (The|An)?\s*(Envoy|Ambassador|High Commissioner|Delegation)\b', r'I bid farewell to the \2', text, flags=re.IGNORECASE)
        text = re.sub(r'\bI Bid Farewell (Cyprus|US|UK|Chinese|EU|UN|German|French|Italian|Indian|Japan|Turkish|Egyptian|Sudanese|Ethiopian|Ugandan|Tanzanian|Rwandan) (Envoy|Ambassador|High Commissioner|Delegation)\b', r'I bid farewell to the \1 \2', text, flags=re.IGNORECASE)
        text = re.sub(r'\bI Met (Cyprus|US|UK|Chinese|EU|UN|German|French|Italian|Indian|Japan|Turkish|Egyptian|Sudanese|Ethiopian|Ugandan|Tanzanian|Rwandan) (Envoy|Ambassador|High Commissioner|Delegation)\b', r'I met with the \1 \2', text, flags=re.IGNORECASE)
        text = re.sub(r'\bI Met (Envoy|Ambassador|High Commissioner|Delegation)\b', r'I met with the \1', text, flags=re.IGNORECASE)
        text = re.sub(r'\bI (Inspected|Launched|Opened|Commissioned|Visited) ([A-Z][a-z]+ Project)\b', r'I \1 the \2', text)
        return text

    # Automated Grammar Engine: Shorthand Normalizer
    def normalize_shorthand(text):
        text = re.sub(r'\b1000s of\b', 'thousands of', text, flags=re.IGNORECASE)
        text = re.sub(r'\b1000s\b', 'thousands', text, flags=re.IGNORECASE)
        text = re.sub(r'\b100s of\b', 'hundreds of', text, flags=re.IGNORECASE)
        text = re.sub(r'\b100s\b', 'hundreds', text, flags=re.IGNORECASE)
        text = re.sub(r'\b10s of\b', 'dozens of', text, flags=re.IGNORECASE)
        return text

    # Automated Grammar Engine: Sentence Case Normalizer
    def to_sentence_case(text):
        if not text:
            return ""
        words = text.split()
        proper_nouns = {'I', 'Sh3.2B', 'Sh3.2b', 'Ksh', 'KSh', 'US', 'UK', 'EU', 'UN', 'Kenya', 'Kenyan', 'Nairobi', 'Mombasa', 'Wajir', 'Narok', 'Kiambu', 'Ruto', 'Cyprus'}
        new_words = []
        for i, word in enumerate(words):
            # Convert ALL CAPS words (e.g. DEVELOPMENT -> development)
            clean_word = word.lower() if (word.isupper() and len(word) > 1 and word not in proper_nouns) else word
            if i == 0:
                new_words.append(clean_word.capitalize())
            elif clean_word in proper_nouns or clean_word.isupper() or re.search(r'\d', clean_word):
                new_words.append(clean_word)
            else:
                new_words.append(clean_word.lower())
        return " ".join(new_words)

    # Automated Grammar Engine: 3rd Person Pronoun Cleaner
    def clean_3rd_person(text):
        text = re.sub(r'\bwhere he launched\.?\b', 'where I launched new infrastructure.', text, flags=re.IGNORECASE)
        text = re.sub(r'\bwhere he (inspected|opened|commissioned)\.?\b', r'where I \1 new projects.', text, flags=re.IGNORECASE)
        text = re.sub(r'\bhe (launched|inspected|commissioned|opened|visited)\b', r'I \1', text, flags=re.IGNORECASE)
        text = re.sub(r'\bhis (administration|government|initiative)\b', r'my \1', text, flags=re.IGNORECASE)
        return text

    # Automated Grammar Engine: Possessive Repair
    def fix_possessives(text):
        text = re.sub(r"\bahead of i's\b", "ahead of my", text, flags=re.IGNORECASE)
        text = re.sub(r"\bahead of I's\b", "ahead of my", text)
        text = re.sub(r"\bi's visit\b", "my visit", text, flags=re.IGNORECASE)
        text = re.sub(r"\bI's visit\b", "My visit", text)
        text = re.sub(r"\bi's\b", "my", text)
        text = re.sub(r"\bI's\b", "My", text)
        return text

    headline = fix_missing_articles(headline)
    headline = normalize_shorthand(headline)
    headline = clean_3rd_person(headline)
    headline = fix_possessives(headline)
    headline = to_sentence_case(headline)

    subtitle = normalize_shorthand(subtitle)
    subtitle = clean_3rd_person(subtitle)
    subtitle = fix_possessives(subtitle)
    subtitle = to_sentence_case(subtitle)
    if subtitle:
        if not subtitle.endswith(('.', '!', '?')):
            subtitle = subtitle + '.'

    # 3. Add Adaptive Logo (Top Right)
    try:
        logo = Image.open(logo_path).convert("RGBA")
        
        # Resize logo to be 180px wide
        logo_w = 180
        l_pct = (logo_w / float(logo.size[0]))
        logo_h = int((float(logo.size[1]) * float(l_pct)))
        logo = logo.resize((logo_w, logo_h), Image.Resampling.LANCZOS)
        
        # Position at top right with 40px padding
        padding = 40
        pos = (target_width - logo_w - padding, padding)

        # Sample luminance in top-right logo region
        top_right_crop = img.crop((pos[0], pos[1], pos[0] + logo_w, pos[1] + logo_h)).convert("L")
        histogram = top_right_crop.histogram()
        total_pixels = sum(histogram)
        avg_luminance = sum(i * count for i, count in enumerate(histogram)) / max(total_pixels, 1)

        # If background is light (high luminance), invert logo colors to black
        if avg_luminance > 130:
            r, g, b, a = logo.split()
            r_inv = r.point(lambda p: 255 - p)
            g_inv = g.point(lambda p: 255 - p)
            b_inv = b.point(lambda p: 255 - p)
            logo = Image.merge("RGBA", (r_inv, g_inv, b_inv, a))

        img.paste(logo, pos, logo)
    except Exception as e:
        print(f"Warning: Could not add logo: {e}", file=sys.stderr)

    # 5. Draw Text with 10% Padding
    font_bold_path = download_font("https://github.com/googlefonts/roboto/raw/main/src/hinted/Roboto-Bold.ttf", "/tmp/Roboto-Bold.ttf")
    font_reg_path = download_font("https://github.com/googlefonts/roboto/raw/main/src/hinted/Roboto-Regular.ttf", "/tmp/Roboto-Regular.ttf")
    
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

    # Dynamic Font Scaling for Headline to ensure it fits in max 2 lines
    font_size = 60
    while font_size >= 40:
        test_font = ImageFont.truetype(font_bold_path, font_size)
        lines = wrap_text(headline, test_font, max_text_width)
        if len(lines) <= 2:
            font_bold = test_font
            headline_lines = lines
            break
        font_size -= 4
    else:
        # Fallback to 40px and take first 2 lines only to prevent overflow
        font_bold = ImageFont.truetype(font_bold_path, 40)
        headline_lines = wrap_text(headline, font_bold, max_text_width)[:2]

    subtitle_lines = wrap_text(subtitle, font_reg, max_text_width)
    
    # 4. Draw Bottom-Only Gradient (Covering only bottom 45% of image height: y = 594 to 1080)
    gradient = Image.new('L', (1, target_height))
    grad_start = int(target_height * 0.55) # 594px
    for y in range(target_height):
        if y < grad_start:
            alpha = 0
        else:
            alpha = int(245 * ((y - grad_start) / (target_height - grad_start)))
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
    for p in [output_path, temp_input_path]:
        try:
            if os.path.exists(p):
                os.remove(p)
        except Exception:
            pass

if __name__ == "__main__":
    if len(sys.argv) < 6:
        print("Usage: python image_overlay.py <image_url> <headline> <subtitle> <output_path> <logo_path>")
        sys.exit(1)
    
    composite_image(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
