using System.Threading;

namespace MsiMenuRepro
{
    internal static class Sleeper
    {
        private static void Main()
        {
            // No window means CloseApplication must wait for its timeout.
            Thread.Sleep(180000);
        }
    }
}
