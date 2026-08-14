{
  pkgs,
  vct-cribl-cli,
  vct-splunk-cli,
}:

let
  inherit (pkgs) python3Packages;
  criblProject = (builtins.fromTOML (builtins.readFile (vct-cribl-cli + "/pyproject.toml"))).project;
  splunkProject =
    (builtins.fromTOML (builtins.readFile (vct-splunk-cli + "/pyproject.toml"))).project;
in
{
  vct-cribl-cli = python3Packages.buildPythonApplication {
    pname = criblProject.name;
    inherit (criblProject) version;
    pyproject = true;
    src = vct-cribl-cli;

    build-system = [ python3Packages.setuptools ];
    dependencies = with python3Packages; [
      click
      httpx
      tabulate
    ];

    doCheck = false;
    pythonImportsCheck = [ "cribl_cli" ];

    meta.mainProgram = builtins.head (builtins.attrNames criblProject.scripts);
  };

  vct-splunk-cli = python3Packages.buildPythonApplication {
    pname = splunkProject.name;
    version = builtins.replaceStrings [ "\n" ] [ "" ] (builtins.readFile (vct-splunk-cli + "/VERSION"));
    pyproject = true;
    src = vct-splunk-cli;

    build-system = [ python3Packages.hatchling ];
    dependencies = with python3Packages; [
      click
      httpx
    ];

    doCheck = false;
    pythonImportsCheck = [ "vct_splunk" ];

    meta.mainProgram = builtins.head (builtins.attrNames splunkProject.scripts);
  };
}
