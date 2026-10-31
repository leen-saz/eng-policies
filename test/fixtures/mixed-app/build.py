import pathlib

out = pathlib.Path("public")
out.mkdir(exist_ok=True)
(out / "index.html").write_text("<h1>ok</h1>\n", encoding="utf-8")
print("built", out / "index.html")
