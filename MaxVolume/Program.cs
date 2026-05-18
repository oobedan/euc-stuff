using NAudio.CoreAudioApi;
using System;
using System.Data;

namespace MicVolumeSetter
{
    class Program
    {
        static void Main(string[] args)
        {
            try
            {
                // Get default recording device (microphone)
                MMDeviceEnumerator enumerator = new MMDeviceEnumerator();
                MMDevice mic = enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Multimedia);

                // Set microphone volume to 100%
                mic.AudioEndpointVolume.MasterVolumeLevelScalar = 1.0f;

                // Console.WriteLine($"Microphone volume set to 100%");
            }
            catch (Exception ex)
            {
                // Console.WriteLine("Error: " + ex.Message);
            }

            //Console.WriteLine("Press any key to exit...");
            //Console.ReadKey();
        }
    }
}
