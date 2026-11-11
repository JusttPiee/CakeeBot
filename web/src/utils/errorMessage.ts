/** The text to show for something that was thrown: the bot's own message when there is one. */
export function errorMessage(problem: unknown): string {
  return problem instanceof Error ? problem.message : String(problem);
}
