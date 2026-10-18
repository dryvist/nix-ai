{ pkgs, instructions }:
{
  catalog-instructions-package =
    pkgs.runCommand "check-catalog-instructions-package"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        ${pkgs.python3}/bin/python - "${instructions.src}" "${instructions.pkg}" <<'PY'
        import os
        import re
        import sys

        source_root, package_root = sys.argv[1:]
        source_files = {
            os.path.relpath(os.path.join(root, name), source_root)
            for root, _, names in os.walk(source_root)
            for name in names
        } - {"index.md"}  # the catalog index is not delivered
        package_files = {
            os.path.relpath(os.path.join(root, name), package_root)
            for root, _, names in os.walk(package_root)
            for name in names
        }
        missing = sorted(source_files - package_files)
        if missing:
            sys.exit(f"instruction package is missing source files: {', '.join(missing)}")

        catalog_keys = re.compile(r"^[ \t]*(?:resource|source_history)[ \t]*:")
        for relative in sorted(package_files):
            if not relative.endswith((".md", ".json")):
                continue
            path = os.path.join(package_root, relative)
            with open(path, encoding="utf-8") as delivered_file:
                lines = delivered_file.readlines()
            if not lines or lines[0].strip() != "---":
                continue
            for line_number, line in enumerate(lines[1:], start=2):
                if line.strip() == "---":
                    break
                if catalog_keys.match(line):
                    sys.exit(f"catalog frontmatter key remains in {relative}:{line_number}")
        PY
        touch "$out"
      '';
}
