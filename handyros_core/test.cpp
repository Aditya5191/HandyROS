#include <chrono>
#include <iostream>
#include <thread>

#include "handyros.h"

int main()
{
    if (!handyros_initialize(0, nullptr))
    {
        std::cout << "DDS initialization failed!" << std::endl;
        return 1;
    }
    std::cout << "DDS initialized, discovering topics for 3s..." << std::endl;

    for (int i = 0; i < 30; ++i)
    {
        handyros_poll();
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    const char* json = handyros_topics_json();
    std::cout << json << std::endl;
    handyros_free_string(json);

    handyros_shutdown();
    return 0;
}
