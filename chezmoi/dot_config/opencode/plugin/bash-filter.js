export const BashFilter = async ({ client, $ }) => {
  const rewrites = [
    { match: /\bdrush\b/, suggestion: "ddev drush" },
    { match: /\bcomposer\b/, suggestion: "ddev composer" },
    { match: /\bnpm\b/, suggestion: "pnpm" },
    { match: /\bpip install\b/, suggestion: "uv tool install" }
  ];

  return {
    tool: {
      execute: {
        before: async (input, output) => {
          if (input.tool === "bash") {
            const cmd = output.args.command;
            for (const { match, suggestion } of rewrites) {
              if (match.test(cmd)) {
                throw new Error(`Use '${suggestion}' instead of '${cmd.match(match)[0]}'`);
              }
            }
          }
        }
      }
    }
  }
}
