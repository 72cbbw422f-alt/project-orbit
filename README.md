# Project Orbit

A clean build repository for a native SwiftUI weather application.

## Build

The project uses XcodeGen and GitHub Actions on a standard GitHub-hosted macOS runner. Pushes to `main` trigger an unsigned iOS build. The resulting IPA is uploaded as a workflow artifact.

## Weather data and privacy

The app requests location permission on the device and sends the resulting coordinates to the Open-Meteo forecast API to retrieve local weather. The app displays the generic label "Din plats"; it does not reverse-geocode coordinates into a town or locality.

Open-Meteo's free API is intended for non-commercial use and requires attribution under CC BY 4.0. See https://open-meteo.com/ for its terms and attribution requirements.

## Installation

The workflow produces an unsigned IPA. An unsigned IPA cannot be installed directly on a physical iPhone; it must be signed with a valid Apple development/distribution identity and provisioning profile.

## Repository scope

This repository contains a clean source snapshot only. It intentionally does not include the original development history, old build artifacts, local configuration, credentials, or personal location data.
