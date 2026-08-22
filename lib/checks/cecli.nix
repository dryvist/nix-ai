# cecli module regression tests
{ pkgs, hmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  cfg = hmConfig.config.programs.cecli;
  skillsDir = hmConfig.config.programs.agentSkills.skillsDir;
  homeFiles = hmConfig.config.home.file;
in
{
  # Verify all expected cecli option paths exist.
  cecli-options-regression = helpers.mkOptionsRegression {
    label = "cecli";
    checkName = "check-cecli-options-regression";
    inherit cfg;
    expectedOptions = [
      "attributeAuthor"
      "attributeCommitter"
      "autoCommits"
      "autoTest"
      "darkMode"
      "dirtyCommits"
      "editFormat"
      "editorModel"
      "enable"
      "extraConfig"
      "gitignore"
      "lint"
      "model"
      "pretty"
      "readFiles"
      "stream"
      "weakEditFormat"
      "weakModel"
    ];
  };

  # cecli has no native skill loader: the shared manifest is injected as
  # always-on read context instead. Assert the path it names is the root that
  # is actually deployed. Copilot carried the same pointer hardcoded to the
  # inactive root, which is exactly the failure this pins against.
  cecli-skill-manifest-path =
    let
      indexPath = "${skillsDir}/INDEX.md";
      conf = homeFiles.".cecli.conf.yml";
    in
    assert
      builtins.hasAttr indexPath homeFiles
      || throw "cecli reads the skill manifest at ${indexPath}, which is not deployed";
    pkgs.runCommand "check-cecli-skill-manifest-path"
      {
        nativeBuildInputs = [ pkgs.gnugrep ];
      }
      ''
        grep -q "${skillsDir}/INDEX.md" ${conf.source} \
          || { echo "cecli config does not read ${skillsDir}/INDEX.md" >&2; exit 1; }
        touch $out
      '';
}
