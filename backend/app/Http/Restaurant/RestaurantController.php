<?php

namespace App\Http\Controllers\Restaurant;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;

class RestaurantController extends Controller
{
    public function store(Request $request)
    {
        return response()->json([
            'message' => 'Restaurant onboarding endpoint ready'
        ]);
    }
}
