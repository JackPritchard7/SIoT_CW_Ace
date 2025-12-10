# ===============================================================
# Ace Tennis Classifier — Header Export (for ESP32)
# ===============================================================

import subprocess
from pathlib import Path

# Folder containing .tflite models
MODEL_DIR = Path("UPDATE_HERE")

# Folder where .h files should be saved
OUTPUT_DIR = Path("UPDATE_HERE")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

MODELS = {
    "idle_swing_model.tflite": ("idle_swing_model_data", "idle_swing_model_data_len"),
    "stroke_type_model.tflite": ("stroke_type_model_data", "stroke_type_model_data_len"),
}

print("⚙️ Converting TensorFlow Lite models to C headers...\n")

for file_name, (array_name, len_name) in MODELS.items():
    model_path = MODEL_DIR / file_name
    header_path = OUTPUT_DIR / (model_path.stem + "_data.h")

    if not model_path.exists():
        print(f"❌ Not found: {model_path}")
        continue

    print(f"🔧 Processing {file_name} → {header_path.name}")

    # Run xxd
    result = subprocess.run(["xxd", "-i", str(model_path)], capture_output=True, text=True)
    if result.returncode != 0:
        print(f"❌ xxd failed for {model_path}")
        continue

    lines = result.stdout.splitlines()

    # ---- Extract ONLY the hex bytes inside { ... } ----
    byte_lines = []
    inside = False

    for line in lines:
        if "{" in line:
            inside = True
            continue
        if "}" in line:
            inside = False
            continue
        if inside:
            byte_lines.append(line.strip())

    # ---- Extract generated length ----
    length_line = next((l for l in lines if "_len" in l and "=" in l), None)
    length_value = length_line.split("=")[1].strip().rstrip(";") if length_line else "0"

    # ---- Create header guard ----
    guard = (model_path.stem.upper() + "_DATA_H").replace(".", "_")

    # ---- Write header ----
    with open(header_path, "w") as f:
        f.write(f"#ifndef {guard}\n")
        f.write(f"#define {guard}\n\n")
        f.write("// AUTO-GENERATED TFLITE MODEL DATA\n\n")

        # main array
        f.write(f"const unsigned char {array_name}[] = {{\n")
        for line in byte_lines:
            f.write(f"  {line}\n")
        f.write("};\n\n")

        # length
        f.write(f"const unsigned int {len_name} = {length_value};\n\n")

        f.write(f"#endif // {guard}\n")

    print(f"✅ Saved: {header_path}\n")

print("🎉 Done! Headers exported directly into your ESP32 /src folder.")
