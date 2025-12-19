<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Restaurant\RestaurantController;

Route::post('/restaurants', [RestaurantController::class, 'store']);
