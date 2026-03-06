export const EnvProtection = async ({ client, $ }) => {
  return {
    tool: {
      execute: {
        before: async (input, output) => {
          if (input.tool === "read" && output.args.filePath.includes(".env")) {
            throw new Error("Access denied: try the .env.example instead or ask for user input")
          }
        }
      }
    }
  }
}
