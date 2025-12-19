<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
    Schema::create('restaurants', function (Blueprint $table) {
        $table->id();

        $table->string('name');
        $table->string('slug')->unique();

        $table->string('phone', 50)->nullable();
        $table->string('email')->nullable();
        $table->text('address')->nullable();

        $table->decimal('service_charge_pct', 5, 2)->default(0.00);
        $table->string('gst_no')->nullable();

        $table->json('languages')->nullable();

        $table->boolean('is_active')->default(true);

        $table->timestamps();
    });
}

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('restaurants');
    }
};
